package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"os"
	"testing"

	"datadog-functions/lib/client"

	fdk "github.com/fnproject/fdk-go"
	"github.com/stretchr/testify/assert"
)

func getContext() context.Context {
	mockCtx := MockFnContext{}
	ctx := context.Background()
	ctx = fdk.WithContext(ctx, mockCtx)
	return ctx
}

type MockFnContext struct {
	HeaderMap http.Header
}

func (m MockFnContext) AppID() string                          { return "mock-app-id" }
func (m MockFnContext) AppName() string                        { return "mock-app-name" }
func (m MockFnContext) FnID() string                           { return "mock-fn-id" }
func (m MockFnContext) FnName() string                         { return "mock-fn-name" }
func (m MockFnContext) CallID() string                         { return "mock-call-id" }
func (m MockFnContext) Config() map[string]string              { return nil }
func (m MockFnContext) Header() http.Header                    { return m.HeaderMap }
func (m MockFnContext) ContentType() string                    { return "" }
func (m MockFnContext) TracingContextData() fdk.TracingContext { return nil }

type mockMetricsDLQ struct {
	writeCalls int
	listPages  [][]string
	readBody   []byte
}

func (m *mockMetricsDLQ) WriteWithGeneratedKey(ctx context.Context, prefix string, payload []byte) (string, error) {
	m.writeCalls++
	return prefix + "test-key.json", nil
}

func (m *mockMetricsDLQ) ListKeysPage(ctx context.Context, prefix string, start *string, limit int) ([]string, *string, error) {
	if len(m.listPages) == 0 {
		return nil, nil, nil
	}
	page := m.listPages[0]
	m.listPages = m.listPages[1:]
	var next *string
	if len(m.listPages) > 0 {
		s := "cursor"
		next = &s
	}
	return page, next, nil
}

func (m *mockMetricsDLQ) Read(ctx context.Context, key string) ([]byte, error) {
	if m.readBody != nil {
		return m.readBody, nil
	}
	return []byte(`{"version":"v1.0","payload":{"headers":{"tenancy_ocid":"ocid1.tenancy","source_fn_app_ocid":"","source_fn_app_name":"","source_fn_ocid":"","source_fn_name":"","source_fn_call_id":""},"body":"{}"}}`), nil
}

func (m *mockMetricsDLQ) Delete(ctx context.Context, key string) error {
	return nil
}

func TestMyHandler(t *testing.T) {
	testCases := []struct {
		name            string
		tenancyOCID     string
		expectedStatus  string
		expectedMessage string
		expectedError   string
		setupDLQ        bool
	}{
		{
			name:            "ErrorGeneratingMetricsMsg",
			tenancyOCID:     "",
			expectedStatus:  "error",
			expectedMessage: "",
			expectedError:   "missing required environment variable TENANCY_OCID",
		},
		{
			name:            "DLQNotConfigured",
			tenancyOCID:     "test-tenancy",
			expectedStatus:  "error",
			expectedMessage: "",
			expectedError:   "DLQ requires DLQ_BUCKET_NAMESPACE and DLQ_BUCKET_REGION",
		},
		{
			name:            "SuccessfulMetricsWrittenToDLQ",
			tenancyOCID:     "test-tenancy",
			expectedStatus:  "success",
			expectedMessage: "Metrics written to DLQ (send to Datadog only via replay)",
			expectedError:   "",
			setupDLQ:        true,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			input := bytes.NewBufferString(`{"metrics": "test-metric"}`)
			output := &bytes.Buffer{}
			if tc.tenancyOCID != "" {
				t.Setenv("TENANCY_OCID", tc.tenancyOCID)
			} else {
				os.Unsetenv("TENANCY_OCID")
			}

			originalDatadogClientFunc := datadogClientFunc
			originalGetMetricsDLQ := getMetricsDLQ
			defer func() {
				datadogClientFunc = originalDatadogClientFunc
				getMetricsDLQ = originalGetMetricsDLQ
			}()
			datadogClientFunc = client.NewTestDatadogClientWithTenancyAndSite

			if tc.setupDLQ {
				t.Setenv("DLQ_BUCKET_NAMESPACE", "test-ns")
				t.Setenv("DLQ_BUCKET_REGION", "us-ashburn-1")
				getMetricsDLQ = func(namespace, bucketName, region string) (metricsDLQ, error) {
					assert.Equal(t, "test-ns", namespace)
					assert.Equal(t, dlqBucketNameMetrics, bucketName)
					assert.Equal(t, "us-ashburn-1", region)
					return &mockMetricsDLQ{}, nil
				}
			} else if tc.name != "ErrorGeneratingMetricsMsg" {
				os.Unsetenv("DLQ_BUCKET_NAMESPACE")
				os.Unsetenv("DLQ_BUCKET_REGION")
			}

			MyHandler(getContext(), input, output)

			var resp fnResponse
			err := json.Unmarshal(output.Bytes(), &resp)

			assert.NoError(t, err)
			assert.Equal(t, tc.expectedStatus, resp.Status)
			assert.Equal(t, tc.expectedMessage, resp.Message)
			if tc.expectedError != "" {
				assert.Contains(t, resp.Error, tc.expectedError)
			} else {
				assert.Empty(t, resp.Error)
			}
		})
	}
}

func TestMyHandlerReplayFromDLQ(t *testing.T) {
	t.Setenv("TENANCY_OCID", "test-tenancy")
	t.Setenv("DLQ_BUCKET_NAMESPACE", "test-ns")
	t.Setenv("DLQ_BUCKET_REGION", "us-ashburn-1")

	originalDatadog := datadogClientFunc
	originalDLQ := getMetricsDLQ
	defer func() {
		datadogClientFunc = originalDatadog
		getMetricsDLQ = originalDLQ
	}()
	datadogClientFunc = client.NewTestDatadogClientWithTenancyAndSite

	mock := &mockMetricsDLQ{
		listPages: [][]string{{"metrics/batch-1.json"}},
	}
	getMetricsDLQ = func(namespace, bucketName, region string) (metricsDLQ, error) {
		return mock, nil
	}

	input := bytes.NewBufferString(`{"replayFromDlq":true}`)
	output := &bytes.Buffer{}
	MyHandler(getContext(), input, output)

	var resp fnResponse
	assert.NoError(t, json.Unmarshal(output.Bytes(), &resp))
	assert.Equal(t, "success", resp.Status)
	assert.Contains(t, resp.Message, "Replay sent 1 metrics batches from DLQ to Datadog")
}

func TestGetSerializedMetricData(t *testing.T) {
	input := bytes.NewBufferString("test input data")

	result, err := getSerializedMetricData(input)

	assert.NoError(t, err)
	assert.Equal(t, "test input data", result)
}
