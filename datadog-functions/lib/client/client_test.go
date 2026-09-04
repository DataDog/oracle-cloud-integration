package client

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

func TestIntakeURL(t *testing.T) {
	cases := []struct {
		name       string
		prefix     string
		path       string
		site       string
		customSite string
		want       string
	}{
		{
			name:   "default dot-joined form",
			prefix: "cloudplatform-intake",
			path:   "/api/v2/cloudchanges",
			site:   "datadoghq.com",
			want:   "https://cloudplatform-intake.datadoghq.com/api/v2/cloudchanges",
		},
		{
			name:   "logs multi-label prefix",
			prefix: "http-intake.logs",
			path:   "/api/v2/logs",
			site:   "datadoghq.eu",
			want:   "https://http-intake.logs.datadoghq.eu/api/v2/logs",
		},
		{
			name:       "custom site provides the full base with dashes",
			prefix:     "cloudplatform-intake",
			path:       "/api/v2/cloudchanges",
			site:       "datadoghq.com",
			customSite: "customerA.mrf.datadoghq.com",
			want:       "https://cloudplatform-intake-customerA.mrf.datadoghq.com/api/v2/cloudchanges",
		},
		{
			name:       "custom site converts prefix dots to dashes",
			prefix:     "http-intake.logs",
			path:       "/api/v2/logs",
			site:       "datadoghq.com",
			customSite: "customerA.mrf.datadoghq.com",
			want:       "https://http-intake-logs-customerA.mrf.datadoghq.com/api/v2/logs",
		},
		{
			name:       "custom site for metrics",
			prefix:     "ocimetrics-intake",
			path:       "/api/v2/ocimetrics",
			site:       "datadoghq.com",
			customSite: "customerA.mrf.datadoghq.com",
			want:       "https://ocimetrics-intake-customerA.mrf.datadoghq.com/api/v2/ocimetrics",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("CUSTOM_DD_SITE", tc.customSite)
			assert.Equal(t, tc.want, IntakeURL(tc.prefix, tc.path, tc.site))
		})
	}
}

func TestSendMessageToDatadog(t *testing.T) {
	testCases := []struct {
		name           string
		mockStatusCode int
		expectError    bool
	}{
		{
			name:           "Success",
			mockStatusCode: 202,
			expectError:    false,
		},
		{
			name:           "DD_API_KEY not set",
			mockStatusCode: 100,
			expectError:    true,
		},
		{
			name:           "DD_API_KEY unauthorized",
			mockStatusCode: 403,
			expectError:    true,
		},
		{
			name:           "Datadog API Fails",
			mockStatusCode: 500,
			expectError:    true,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			mockDatadogClient, _ := getTestDatadogClient()

			// Mock Datadog API response
			mockResponse := &http.Response{
				StatusCode: tc.mockStatusCode,
				Body:       io.NopCloser(bytes.NewBufferString("")),
			}
			mockClient := mockDatadogClient.client.(*MockAPIClient)
			mockClient.On("CallAPI", mock.Anything).Return(mockResponse, nil)

			// Call the function with a mock client
			err := mockDatadogClient.SendMessageToDatadog(context.TODO(), []byte(`{"message":"test"}`), "https://test-intake.test.hq.com/api/v2/test")

			// Validate
			if tc.expectError {
				if tc.mockStatusCode == 403 {
					assert.ErrorContains(t, err, "failed to create resource principal provider")
				}
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
			}

			mockClient.AssertExpectations(t)
		})
	}
}
