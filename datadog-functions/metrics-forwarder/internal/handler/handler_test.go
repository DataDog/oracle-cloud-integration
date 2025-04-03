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
}

func (m MockFnContext) AppID() string                          { return "mock-app-id" }
func (m MockFnContext) AppName() string                        { return "mock-app-name" }
func (m MockFnContext) FnID() string                           { return "mock-fn-id" }
func (m MockFnContext) FnName() string                         { return "mock-fn-name" }
func (m MockFnContext) CallID() string                         { return "mock-call-id" }
func (m MockFnContext) Config() map[string]string              { return nil }
func (m MockFnContext) Header() http.Header                    { return nil }
func (m MockFnContext) ContentType() string                    { return "" }
func (m MockFnContext) TracingContextData() fdk.TracingContext { return nil }

func TestMyHandler(t *testing.T) {
	testCases := []struct {
		name            string
		tenancyOCID     string
		expectedStatus  string
		expectedMessage string
		expectedError   string
	}{
		{
			name:            "ErrorGeneratingMetricsMsg",
			tenancyOCID:     "",
			expectedStatus:  "error",
			expectedMessage: "",
			expectedError:   "missing required environment variable TENANCY_OCID",
		},
		{
			name:            "SuccessfulMetricsHandling",
			tenancyOCID:     "test-tenancy",
			expectedStatus:  "success",
			expectedMessage: "Metrics sent to Datadog",
			expectedError:   "",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			input := bytes.NewBufferString(`{"metrics": "test-metric"}`)
			output := &bytes.Buffer{}
			if tc.tenancyOCID != "" {
				os.Setenv("TENANCY_OCID", tc.tenancyOCID)
				defer os.Unsetenv("TENANCY_OCID")
			}

			originalDatadogClientFunc := datadogClientFunc
			defer func() {
				datadogClientFunc = originalDatadogClientFunc
			}()
			datadogClientFunc = client.NewTestDatadogClientWithTenancyAndSite

			MyHandler(getContext(), input, output)

			var resp fnResponse
			err := json.Unmarshal(output.Bytes(), &resp)

			assert.NoError(t, err)
			assert.Equal(t, tc.expectedStatus, resp.Status)
			assert.Equal(t, tc.expectedMessage, resp.Message)
			assert.Equal(t, tc.expectedError, resp.Error)
		})
	}
}

func TestGetSerializedMetricData(t *testing.T) {
	input := bytes.NewBufferString("test input data")

	result, err := getSerializedMetricData(input)

	assert.NoError(t, err)
	assert.Equal(t, "test input data", result)
}
