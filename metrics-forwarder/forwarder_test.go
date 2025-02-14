package main

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/url"
	"os"
	"testing"

	datadog "github.com/DataDog/datadog-api-client-go/v2/api/datadog"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

// Mock HTTP Client for Datadog API
type MockAPIClient struct {
	mock.Mock
}

// Mock `CallAPI` method to simulate API response
func (m *MockAPIClient) CallAPI(req *http.Request) (*http.Response, error) {
	args := m.Called(req)
	return args.Get(0).(*http.Response), args.Error(1)
}

// Mock `PrepareRequest` method to simulate API request
func (m *MockAPIClient) PrepareRequest(ctx context.Context, path string, method string, postBody interface{}, headerParams map[string]string, queryParams url.Values, formParams url.Values, fileName *datadog.FormFile) (*http.Request, error) {
	apiClient := createApiClient()
	return apiClient.PrepareRequest(ctx, path, method, postBody, headerParams, queryParams, formParams, fileName)
}

func TestSendMetricsToDatadog(t *testing.T) {
	testCases := []struct {
		name           string
		apiKey         string
		compressed     bool
		mockStatusCode int
		expectError    bool
	}{
		{
			name:           "Success",
			apiKey:         "valid_api_key",
			compressed:     true,
			mockStatusCode: 202,
			expectError:    false,
		},
		{
			name:           "DD_API_KEY not set",
			apiKey:         "",
			compressed:     true,
			mockStatusCode: 100,
			expectError:    true,
		},
		{
			name:           "DD_API_KEY unauthorized",
			apiKey:         "invalid_api_key",
			compressed:     true,
			mockStatusCode: 401,
			expectError:    true,
		},
		{
			name:           "Compressed payload set to false",
			apiKey:         "valid_api_key",
			compressed:     false,
			mockStatusCode: 202,
			expectError:    false,
		},
		{
			name:           "Datadog API Fails",
			apiKey:         "valid_api_key",
			compressed:     true,
			mockStatusCode: 500,
			expectError:    true,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			mockClient := new(MockAPIClient)
			// Set environment variable
			if tc.compressed {
				os.Setenv("DD_COMPRESS", "true")
			} else {
				os.Setenv("DD_COMPRESS", "false")
			}
			defer os.Unsetenv("DD_COMPRESS")
			if tc.apiKey != "" {
				os.Setenv("DD_SITE", "test.com")
				defer os.Unsetenv("DD_SITE")
				os.Setenv("DD_API_KEY", tc.apiKey)
				defer os.Unsetenv("DD_API_KEY")
			}

			// Mock Datadog API response
			mockResponse := &http.Response{
				StatusCode: tc.mockStatusCode,
				Body:       io.NopCloser(bytes.NewBufferString("")),
			}

			mockClient.On("CallAPI", mock.Anything).Return(mockResponse, nil)

			// Call the function with a mock client
			err := sendMetricsToDatadog(mockClient, []byte(`{"metrics":"test"}`))

			// Validate
			if tc.expectError {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
			}

			if tc.apiKey != "" {
				mockClient.AssertExpectations(t)
			}
		})
	}
}
