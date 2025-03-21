package client

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"time"

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
	vaultRegion string
	secretOCID  string
}

// SendMessageToDatadog sends a message to Datadog. If the initial attempt fails with a 403 status code,
// it tries to refresh the API key and resend the message.
//
// Parameters:
//
//	ctx - The context for the request.
//	message - The message to be sent as a byte slice.
//	url - The URL to which the message should be sent.
//
// Returns:
//
//	error - An error if the message could not be sent or if the API key could not be refreshed.
func (client *DatadogClient) SendMessageToDatadog(ctx context.Context, message []byte, url string) error {
	ctx, cancel := context.WithTimeout(ctx, 3*time.Minute)
	defer cancel() // releases resources if sendMessage or refreshAPIKey completes before timeout elapses
	status, err := client.sendMessage(ctx, message, url)
	if err != nil && status == http.StatusForbidden {
		// Attempt to fetch the API key again in case it has been rotated
		err = client.refreshAPIKey(ctx)
		if err != nil {
			return err
		}
		_, err = client.sendMessage(ctx, message, url)
		return err
	}
	return err
}

func (client *DatadogClient) sendMessage(ctx context.Context, message []byte, url string) (int, error) {
	apiHeaders := map[string]string{
		"Content-Encoding": "gzip",
		"Content-Type":     "application/json",
		"DD-API-KEY":       client.ApiKey,
	}
	fmt.Printf("Uncompressed payload size=%d\n", len(message))
	req, err := client.Client.PrepareRequest(ctx, url, http.MethodPost, message, apiHeaders, nil, nil, nil)
	if err != nil {
		return http.StatusInternalServerError, err
	}

	resp, err := client.Client.CallAPI(req)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		log.Printf("Error: Received non-200 response from Datadog: %d", resp.StatusCode)
		body, err := datadog.ReadBody(resp)
		if err == nil {
			log.Printf("Error response body: %s", string(body))
		}
		return resp.StatusCode, errors.New("failed to send message to Datadog")
	}
	return resp.StatusCode, nil
}

func NewDatadogClient() (DatadogClient, error) {
	if cache != nil {
		return *cache, nil
	}
	secretOCID := os.Getenv("API_KEY_SECRET_OCID")
	homeRegion := os.Getenv("HOME_REGION")
	if secretOCID == "" || homeRegion == "" {
		return DatadogClient{}, errors.New("missing one of the required environment variables: API_KEY_SECRET_OCID, HOME_REGION")
	}

	configuration := datadog.NewConfiguration()
	configuration.RetryConfiguration.EnableRetry = true
	client := datadog.NewAPIClient(configuration)

	cache = &DatadogClient{
		Client:      client,
		secretOCID:  secretOCID,
		vaultRegion: homeRegion,
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel() // releases resources if fetchAPIKeyFromVault completes before timeout elapses
	apiKey, err := cache.fetchAPIKeyFromVault(ctx)
	if err != nil {
		return DatadogClient{}, err
	}
	cache.ApiKey = apiKey
	return *cache, nil
}

func NewDatadogClientWithSite() (DatadogClient, string, error) {
	site := os.Getenv("DD_SITE")
	if site == "" {
		return DatadogClient{}, "", errors.New("missing required environment variable DD_SITE")
	}
	client, err := NewDatadogClient()
	return client, site, err
}

func NewDatadogClientWithTenancyAndSite() (DatadogClient, string, string, error) {
	tenancyOCID := os.Getenv("TENANCY_OCID")
	if tenancyOCID == "" {
		return DatadogClient{}, "", "", errors.New("missing required environment variable TENANCY_OCID")
	}
	client, site, err := NewDatadogClientWithSite()
	return client, tenancyOCID, site, err
}
