package common

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/url"

	datadog "github.com/DataDog/datadog-api-client-go/v2/api/datadog"
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
	return &http.Request{}, nil
}

func GetDefaultTestDatadogClient() (DatadogClient, error) {
	ddclient, _ := getTestDatadogClient()
	// Mock Datadog API response
	mockResponse := &http.Response{
		StatusCode: http.StatusAccepted,
		Body:       io.NopCloser(bytes.NewBufferString("")),
	}
	mockClient := ddclient.Client.(*MockAPIClient)
	mockClient.On("CallAPI", mock.Anything).Return(mockResponse, nil)
	return ddclient, nil
}

func getTestDatadogClient() (DatadogClient, error) {
	configuration := datadog.NewConfiguration()
	configuration.RetryConfiguration.EnableRetry = true
	mockClient := new(MockAPIClient)
	return DatadogClient{
		Client: mockClient,
		ApiKey: "apiKey",
	}, nil
}
