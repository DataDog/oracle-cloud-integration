package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"testing"

	"metrics-forwarder/internal/client"

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
		mockSendFunc    func(client client.DatadogClient, metricsMessage []byte) error
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
			expectedError:   "missing one of the required environment variables: TENANCY_OCID, DD_SITE, DD_API_KEY",
		},
		{
			name:        "ErrorSendingMetrics",
			tenancyOCID: "test-tenancy",
			mockSendFunc: func(client client.DatadogClient, metricsMessage []byte) error {
				return fmt.Errorf("error sending metrics to Datadog")
			},
			expectedStatus:  "error",
			expectedMessage: "",
			expectedError:   "error sending metrics to Datadog",
		},
		{
			name:        "SuccessfulMetricsHandling",
			tenancyOCID: "test-tenancy",
			mockSendFunc: func(client client.DatadogClient, metricsMessage []byte) error {
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
				os.Setenv("DD_SITE", "test-site")
				defer os.Unsetenv("DD_SITE")
				os.Setenv("DD_API_KEY", "test-api")
				defer os.Unsetenv("DD_API_KEY")
				os.Setenv("TENANCY_OCID", tc.tenancyOCID)
				defer os.Unsetenv("TENANCY_OCID")
			}

			originalSendFunc := sendMetricsFunc
			defer func() { sendMetricsFunc = originalSendFunc }()

			if tc.mockSendFunc != nil {
				sendMetricsFunc = tc.mockSendFunc
			}

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

func TestNewDatadogClientWithTenancy(t *testing.T) {
	testCases := []struct {
		name        string
		tenancyOCID string
		site        string
		apiKey      string
		expectError bool
	}{
		{
			name:        "EnvVarsSetSuccessfully",
			tenancyOCID: "test-tenancy",
			site:        "test-site",
			apiKey:      "test-api",
			expectError: false,
		},
		{
			name:        "EnvVarsNotSet",
			tenancyOCID: "",
			site:        "",
			apiKey:      "",
			expectError: true,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			if tc.tenancyOCID != "" {
				os.Setenv("TENANCY_OCID", tc.tenancyOCID)
				defer os.Unsetenv("TENANCY_OCID")
			} else {
				os.Unsetenv("TENANCY_OCID")
			}

			if tc.site != "" {
				os.Setenv("DD_SITE", tc.site)
				defer os.Unsetenv("DD_SITE")
			} else {
				os.Unsetenv("DD_SITE")
			}

			if tc.apiKey != "" {
				os.Setenv("DD_API_KEY", tc.apiKey)
				defer os.Unsetenv("DD_API_KEY")
			} else {
				os.Unsetenv("DD_API_KEY")
			}

			ddclient, tenancyOCID, err := newDatadogClientWithTenancy()

			if tc.expectError {
				assert.Error(t, err)
				assert.Equal(t, ddclient, client.DatadogClient{})
				assert.Equal(t, tenancyOCID, "")
			} else {
				assert.NoError(t, err)
				assert.NotEqual(t, ddclient, client.DatadogClient{})
				assert.Equal(t, tenancyOCID, tc.tenancyOCID)
			}
		})
	}
}
