package main

import (
	"bytes"
	"io"
	"net/http"
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

// Mock HTTP Client for Datadog API
type MockHTTPClient struct {
	mock.Mock
}

// Mock `Do` method to simulate API response
func (m *MockHTTPClient) Do(req *http.Request) (*http.Response, error) {
	args := m.Called(req)
	return args.Get(0).(*http.Response), args.Error(1)
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
			mockClient := new(MockHTTPClient)

			// Set environment variable
			if tc.compressed {
				os.Setenv("DD_COMPRESS", "true")
			} else {
				os.Setenv("DD_COMPRESS", "false")
			}
			defer os.Unsetenv("DD_COMPRESS")
			if tc.apiKey != "" {
				os.Setenv("DD_INTAKE_HOST", "test.com")
				defer os.Unsetenv("DD_INTAKE_HOST")
				os.Setenv("DD_API_KEY", tc.apiKey)
				defer os.Unsetenv("DD_API_KEY")
			}

			// Mock Datadog API response
			mockResponse := &http.Response{
				StatusCode: tc.mockStatusCode,
				Body:       io.NopCloser(bytes.NewBufferString("")),
			}

			mockClient.On("Do", mock.Anything).Return(mockResponse, nil)

			// Call the function with a mock client
			err := sendMetricsToDatadog([]byte(`{"metrics":"test"}`), mockClient)

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
