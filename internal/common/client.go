package common

import (
	"context"
	"errors"
	"net/http"
	"net/url"
	"os"

	datadog "github.com/DataDog/datadog-api-client-go/v2/api/datadog"
)

var cache *DatadogClient

type apiClient interface {
	CallAPI(req *http.Request) (*http.Response, error)
	PrepareRequest(ctx context.Context, path string, method string, postBody interface{}, headerParams map[string]string, queryParams url.Values, formParams url.Values, fileName *datadog.FormFile) (*http.Request, error)
}

type DatadogClient struct {
	Client      apiClient
	ApiKey      string
	Site        string
	vaultRegion string
	secretOCID  string
}

func NewDatadogClient() (DatadogClient, error) {
	if cache != nil {
		return *cache, nil
	}
	site := os.Getenv("DD_SITE")
	secretOCID := os.Getenv("API_KEY_SECRET_OCID")
	homeRegion := os.Getenv("HOME_REGION")
	if site == "" || secretOCID == "" || homeRegion == "" {
		return DatadogClient{}, errors.New("missing one of the required environment variables: DD_SITE, API_KEY_SECRET_OCID, HOME_REGION")
	}

	configuration := datadog.NewConfiguration()
	configuration.RetryConfiguration.EnableRetry = true
	client := datadog.NewAPIClient(configuration)

	cache = &DatadogClient{
		Client:      client,
		Site:        site,
		secretOCID:  secretOCID,
		vaultRegion: homeRegion,
	}
	apiKey, err := cache.fetchAPIKeyFromVault(context.Background())
	if err != nil {
		return DatadogClient{}, err
	}
	cache.ApiKey = apiKey
	return *cache, nil
}
