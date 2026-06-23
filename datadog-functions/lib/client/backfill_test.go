package client

import (
	"bytes"
	"context"
	"errors"
	"io"
	"net/http"
	"testing"

	"github.com/oracle/oci-go-sdk/v65/objectstorage"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

// Tier 2: the 5xx-detection contract — sendMessage must invoke the backfill
// handler only for 5xx responses, forwarding the original payload and url.
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
			mockClient := c.client.(*MockAPIClient)
			mockClient.On("CallAPI", mock.Anything).Return(&http.Response{
				StatusCode: tc.code,
				Body:       io.NopCloser(bytes.NewBufferString("")),
			}, nil)

			c.sendMessage(context.TODO(), []byte(payload), intakeURL)

			assert.Equal(t, tc.wantBackfill, called)
			if tc.wantBackfill {
				assert.Equal(t, []byte(payload), gotMessage)
				assert.Equal(t, intakeURL, gotURL)
			}
		})
	}
}

// fakeObjectStorage implements objectStorageAPI for tests, recording PutObject
// calls and returning canned errors for HeadBucket / PutObject.
type fakeObjectStorage struct {
	headErr  error // non-nil => bucket treated as missing
	putErr   error
	putCalls []objectstorage.PutObjectRequest
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

// Tier 3: the persist flow inside handleServerErrorPayload.
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
			orig := newObjectStorageClientFunc
			newObjectStorageClientFunc = func() (objectStorageAPI, error) { return fake, nil }
			defer func() { newObjectStorageClientFunc = orig }()

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
