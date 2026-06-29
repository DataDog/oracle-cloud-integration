package client

import (
	"bytes"
	"context"
	"errors"
	"io"
	"net/http"
	"testing"

	"github.com/oracle/oci-go-sdk/v65/common"
	"github.com/oracle/oci-go-sdk/v65/objectstorage"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

// okResponse builds a canned Datadog API response with the given status code.
func okResponse(status int) *http.Response {
	return &http.Response{StatusCode: status, Body: io.NopCloser(bytes.NewBufferString(""))}
}

// swapOSClient injects fake as the object-storage client and returns a restore func.
func swapOSClient(fake objectStorageAPI) func() {
	orig := newObjectStorageClientFunc
	newObjectStorageClientFunc = func() (objectStorageAPI, error) { return fake, nil }
	return func() { newObjectStorageClientFunc = orig }
}

// Tier 2: the 5xx-detection contract — the forward path (SendMessageToDatadog)
// must invoke the backfill handler only for 5xx responses.
func TestSendMessageBackfillTriggeredOnlyOn5xx(t *testing.T) {
	cases := []struct {
		name         string
		code         int
		wantBackfill bool
	}{
		{"2xx no backfill", 202, false},
		{"4xx no backfill", 400, false},
		{"403 no backfill", 403, false},
		{"500 backfill", 500, true},
		{"502 backfill", 502, true},
		{"599 backfill", 599, true},
	}

	const payload = `{"message":"test"}`
	const intakeURL = "https://x/api/v2/logs"

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var called bool
			var gotMessage []byte
			var gotURL string
			orig := handleServerErrorPayload
			handleServerErrorPayload = func(_ context.Context, message []byte, url string) {
				called, gotMessage, gotURL = true, message, url
			}
			defer func() { handleServerErrorPayload = orig }()

			c, _ := getTestDatadogClient()
			c.client.(*MockAPIClient).On("CallAPI", mock.Anything).Return(okResponse(tc.code), nil)

			_ = c.SendMessageToDatadog(context.TODO(), []byte(payload), intakeURL)

			assert.Equal(t, tc.wantBackfill, called)
			if tc.wantBackfill {
				assert.Equal(t, []byte(payload), gotMessage)
				assert.Equal(t, intakeURL, gotURL)
			}
		})
	}
}

// fakeObjectStorage implements objectStorageAPI for tests. It covers both the
// write path (HeadBucket/PutObject) and the backfill read path
// (ListObjects/GetObject/DeleteObject), recording calls for assertions.
type fakeObjectStorage struct {
	// write path
	headErr  error // non-nil => bucket treated as missing
	putErr   error
	putCalls []objectstorage.PutObjectRequest

	// backfill read path
	objects      []string          // names returned by ListObjects
	contents     map[string][]byte // name -> bytes returned by GetObject
	listErr      error
	getErr       error
	deleteErr    error
	deletedNames []string
}

func (f *fakeObjectStorage) GetNamespace(context.Context, objectstorage.GetNamespaceRequest) (objectstorage.GetNamespaceResponse, error) {
	ns := "test-namespace"
	return objectstorage.GetNamespaceResponse{Value: &ns}, nil
}

func (f *fakeObjectStorage) HeadBucket(context.Context, objectstorage.HeadBucketRequest) (objectstorage.HeadBucketResponse, error) {
	return objectstorage.HeadBucketResponse{}, f.headErr
}

func (f *fakeObjectStorage) PutObject(_ context.Context, req objectstorage.PutObjectRequest) (objectstorage.PutObjectResponse, error) {
	f.putCalls = append(f.putCalls, req)
	return objectstorage.PutObjectResponse{}, f.putErr
}

func (f *fakeObjectStorage) ListObjects(context.Context, objectstorage.ListObjectsRequest) (objectstorage.ListObjectsResponse, error) {
	if f.listErr != nil {
		return objectstorage.ListObjectsResponse{}, f.listErr
	}
	summaries := make([]objectstorage.ObjectSummary, 0, len(f.objects))
	for _, name := range f.objects {
		summaries = append(summaries, objectstorage.ObjectSummary{Name: common.String(name)})
	}
	return objectstorage.ListObjectsResponse{ListObjects: objectstorage.ListObjects{Objects: summaries}}, nil
}

func (f *fakeObjectStorage) GetObject(_ context.Context, req objectstorage.GetObjectRequest) (objectstorage.GetObjectResponse, error) {
	if f.getErr != nil {
		return objectstorage.GetObjectResponse{}, f.getErr
	}
	var data []byte
	if req.ObjectName != nil {
		data = f.contents[*req.ObjectName]
	}
	return objectstorage.GetObjectResponse{Content: io.NopCloser(bytes.NewReader(data))}, nil
}

func (f *fakeObjectStorage) DeleteObject(_ context.Context, req objectstorage.DeleteObjectRequest) (objectstorage.DeleteObjectResponse, error) {
	if req.ObjectName != nil {
		f.deletedNames = append(f.deletedNames, *req.ObjectName)
	}
	return objectstorage.DeleteObjectResponse{}, f.deleteErr
}

// Tier 3: the persist flow inside handleServerErrorPayload (the write path).
func TestHandleServerErrorPayload(t *testing.T) {
	cases := []struct {
		name       string
		url        string
		headErr    error
		putErr     error
		wantPut    bool
		wantBucket string
	}{
		{"persists to logs bucket when it exists", "https://x/api/v2/logs", nil, nil, true, "dd-logs-backfill"},
		{"persists to metrics bucket when it exists", "https://x/api/v2/ocimetrics", nil, nil, true, "dd-metrics-backfill"},
		{"drops when bucket missing", "https://x/api/v2/logs", errors.New("404 not found"), nil, false, ""},
		{"skips unknown data type", "https://x/api/v2/unknown", nil, nil, false, ""},
		{"handles put error gracefully", "https://x/api/v2/ocimetrics", nil, errors.New("boom"), true, "dd-metrics-backfill"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			fake := &fakeObjectStorage{headErr: tc.headErr, putErr: tc.putErr}
			defer swapOSClient(fake)()

			handleServerErrorPayload(context.TODO(), []byte(`{"k":"v"}`), tc.url)

			if tc.wantPut {
				assert.Len(t, fake.putCalls, 1)
				assert.Equal(t, tc.wantBucket, *fake.putCalls[0].BucketName)
			} else {
				assert.Empty(t, fake.putCalls)
			}
		})
	}
}

// The backfill drain loop: replay each object, delete on success, leave on failure.
func TestBackfill(t *testing.T) {
	const intakeURL = "https://x/api/v2/logs"

	t.Run("replays and deletes each object on success", func(t *testing.T) {
		c, _ := getTestDatadogClient()
		mockClient := c.client.(*MockAPIClient)
		mockClient.On("CallAPI", mock.Anything).Return(okResponse(202), nil)

		fake := &fakeObjectStorage{
			objects:  []string{"a.json", "b.json"},
			contents: map[string][]byte{"a.json": []byte(`{"a":1}`), "b.json": []byte(`{"b":2}`)},
		}
		defer swapOSClient(fake)()

		summary, err := c.Backfill(context.TODO(), intakeURL)
		assert.NoError(t, err)
		assert.ElementsMatch(t, []string{"a.json", "b.json"}, fake.deletedNames)
		// the bucket bytes actually reached the Datadog send
		assert.ElementsMatch(t, [][]byte{[]byte(`{"a":1}`), []byte(`{"b":2}`)}, mockClient.SentBodies)
		assert.Empty(t, fake.putCalls, "replay must not re-bucket")
		assert.Equal(t, BackfillSummary{Replayed: 2}, summary)
	})

	t.Run("stops and leaves object when send fails after retry", func(t *testing.T) {
		c, _ := getTestDatadogClient()
		c.client.(*MockAPIClient).On("CallAPI", mock.Anything).Return(okResponse(500), nil)

		fake := &fakeObjectStorage{
			objects:  []string{"a.json"},
			contents: map[string][]byte{"a.json": []byte(`{"a":1}`)},
		}
		defer swapOSClient(fake)()

		summary, err := c.Backfill(context.TODO(), intakeURL)
		assert.Error(t, err)
		assert.Empty(t, fake.deletedNames, "a failed replay must leave the object in the bucket")
		assert.Empty(t, fake.putCalls, "replay must not re-bucket on failure")
		assert.Zero(t, summary.Replayed)
	})

	t.Run("waits then retries on 429 and succeeds", func(t *testing.T) {
		orig := throttleBackoff
		throttleBackoff = 0
		defer func() { throttleBackoff = orig }()

		c, _ := getTestDatadogClient()
		mockClient := c.client.(*MockAPIClient)
		mockClient.On("CallAPI", mock.Anything).Return(okResponse(429), nil).Once()
		mockClient.On("CallAPI", mock.Anything).Return(okResponse(202), nil)

		fake := &fakeObjectStorage{
			objects:  []string{"a.json"},
			contents: map[string][]byte{"a.json": []byte(`{"a":1}`)},
		}
		defer swapOSClient(fake)()

		summary, err := c.Backfill(context.TODO(), intakeURL)
		assert.NoError(t, err)
		assert.Equal(t, []string{"a.json"}, fake.deletedNames)
		assert.Equal(t, 1, summary.Replayed)
	})

	t.Run("counts delivered-but-not-deleted objects", func(t *testing.T) {
		c, _ := getTestDatadogClient()
		c.client.(*MockAPIClient).On("CallAPI", mock.Anything).Return(okResponse(202), nil)

		fake := &fakeObjectStorage{
			objects:   []string{"a.json"},
			contents:  map[string][]byte{"a.json": []byte(`{"a":1}`)},
			deleteErr: errors.New("delete boom"),
		}
		defer swapOSClient(fake)()

		summary, err := c.Backfill(context.TODO(), intakeURL)
		assert.NoError(t, err, "a delete failure is non-fatal")
		assert.Equal(t, 1, summary.Replayed)
		assert.Equal(t, 1, summary.DeleteFailures)
	})

	t.Run("empty bucket is a no-op", func(t *testing.T) {
		c, _ := getTestDatadogClient()
		fake := &fakeObjectStorage{}
		defer swapOSClient(fake)()

		summary, err := c.Backfill(context.TODO(), intakeURL)
		assert.NoError(t, err)
		assert.Empty(t, fake.deletedNames)
		assert.Equal(t, BackfillSummary{}, summary)
	})

	t.Run("unrecognized intake url returns an error", func(t *testing.T) {
		c, _ := getTestDatadogClient()
		fake := &fakeObjectStorage{}
		defer swapOSClient(fake)()

		_, err := c.Backfill(context.TODO(), "https://x/api/v2/unknown")
		assert.Error(t, err)
	})
}
