package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"testing"

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
	appID   string
	appName string
	fnID    string
	fnName  string
	callID  string
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
		mockSendFunc    func(metricsMessage []byte, client HTTPClient) error
		expectedStatus  string
		expectedMessage string
		expectedError   string
	}{
		{
			name:            "ErrorGeneratingMetricsMsg",
			tenancyOCID:     "",
			mockSendFunc:    nil,
			expectedStatus:  "error",
			expectedMessage: "",
			expectedError:   "missing environment variable: TENANCY_OCID",
		},
		{
			name:        "ErrorSendingMetrics",
			tenancyOCID: "test-tenancy",
			mockSendFunc: func(metricsMessage []byte, client HTTPClient) error {
				return fmt.Errorf("error sending metrics to Datadog")
			},
			expectedStatus:  "error",
			expectedMessage: "",
			expectedError:   "error sending metrics to Datadog",
		},
		{
			name:        "SuccessfulMetricsHandling",
			tenancyOCID: "test-tenancy",
			mockSendFunc: func(metricsMessage []byte, client HTTPClient) error {
				return nil
			},
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

			originalSendFunc := sendMetricsFunc
			defer func() { sendMetricsFunc = originalSendFunc }()

			if tc.mockSendFunc != nil {
				sendMetricsFunc = tc.mockSendFunc
			}

			myHandler(getContext(), input, output)

			var resp FnResponse
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
