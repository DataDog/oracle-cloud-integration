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
			mockClient := mockDatadogClient.Client.(*MockAPIClient)
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
