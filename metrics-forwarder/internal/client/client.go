package client

import (
	"context"
	"net/http"
	"net/url"

	datadog "github.com/DataDog/datadog-api-client-go/v2/api/datadog"
)

var cache *DatadogClient

type apiClient interface {
	CallAPI(req *http.Request) (*http.Response, error)
	PrepareRequest(ctx context.Context, path string, method string, postBody interface{}, headerParams map[string]string, queryParams url.Values, formParams url.Values, fileName *datadog.FormFile) (*http.Request, error)
}

type DatadogClient struct {
	Client apiClient
	site   string
	apiKey string
}

func NewDatadogClient(site, apiKey string) DatadogClient {
	if cache != nil && cache.site == site && cache.apiKey == apiKey {
		return *cache
	}

	configuration := datadog.NewConfiguration()
	configuration.RetryConfiguration.EnableRetry = true
	client := datadog.NewAPIClient(configuration)

	cache = &DatadogClient{
		Client: client,
		site:   site,
		apiKey: apiKey,
	}

	return *cache
}
