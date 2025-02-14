package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"

	datadog "github.com/DataDog/datadog-api-client-go/v2/api/datadog"
)

type APIClient interface {
	CallAPI(req *http.Request) (*http.Response, error)
	PrepareRequest(ctx context.Context, path string, method string, postBody interface{}, headerParams map[string]string, queryParams url.Values, formParams url.Values, fileName *datadog.FormFile) (*http.Request, error)
}

func createApiClient() *datadog.APIClient {
	configuration := datadog.NewConfiguration()
	configuration.RetryConfiguration.EnableRetry = true
	client := datadog.NewAPIClient(configuration)

	return client
}

func sendMetricsToDatadog(client APIClient, metricsMessage []byte) error {
	site := os.Getenv("DD_SITE")
	apiKey := os.Getenv("DD_API_KEY")

	if site == "" || apiKey == "" {
		return errors.New("missing one of the required environment variables: DD_SITE, DD_API_KEY")
	}

	apiHeaders := map[string]string{
		"Content-Type": "application/json",
		"DD-API-KEY":   apiKey,
	}
	fmt.Printf("Uncompressed payload size=%d\n", len(metricsMessage))
	if shouldCompressPayload() {
		apiHeaders["Content-Encoding"] = "gzip"
	}

	url := fmt.Sprintf("https://ocimetrics-intake.%s/api/v2/ocimetrics", site)
	req, err := client.PrepareRequest(nil, url, http.MethodPost, metricsMessage, apiHeaders, nil, nil, nil)
	if err != nil {
		return err
	}

	resp, err := client.CallAPI(req)
	if err != nil {
		return err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		log.Printf("Error: Received non-200 response from Datadog: %d", resp.StatusCode)
		body, err := datadog.ReadBody(resp)
		if err == nil {
			log.Printf("Error response body: %s", string(body))
		}
		return errors.New("failed to send metrics to Datadog")
	}
	return nil
}

func shouldCompressPayload() bool {
	return strings.ToLower(os.Getenv("DD_COMPRESS")) == "true"
}
