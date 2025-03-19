package forwarder

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"oracle-cloud-integration/internal/common"

	datadog "github.com/DataDog/datadog-api-client-go/v2/api/datadog"
)

// SendMetricsToDatadog sends the provided metrics message to Datadog.
// It prepares the request with the necessary headers, including the API key
// and optionally gzip compression if required. The function then sends the
// request to the Datadog API and checks the response status code.
//
// Parameters:
//   - client: A DatadogClient instance containing the API key and HTTP client.
//   - metricsMessage: A byte slice containing the metrics data to be sent.
//
// Returns:
//   - error: An error if the request preparation or API call fails, or if the
//     response status code indicates a failure.
func SendMetrics(ctx context.Context, client common.DatadogClient, metricsMessage []byte) (int, error) {
	apiHeaders := map[string]string{
		"Content-Type": "application/json",
		"DD-API-KEY":   client.ApiKey,
	}
	fmt.Printf("Uncompressed payload size=%d\n", len(metricsMessage))

	url := fmt.Sprintf("https://ocimetrics-intake.%s/api/v2/ocimetrics", client.Site)
	req, err := client.Client.PrepareRequest(ctx, url, http.MethodPost, metricsMessage, apiHeaders, nil, nil, nil)
	if err != nil {
		return 500, err
	}

	resp, err := client.Client.CallAPI(req)
	if err != nil {
		return 500, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		log.Printf("Error: Received non-200 response from Datadog: %d", resp.StatusCode)
		body, err := datadog.ReadBody(resp)
		if err == nil {
			log.Printf("Error response body: %s", string(body))
		}
		return resp.StatusCode, errors.New("failed to send metrics to Datadog")
	}
	return resp.StatusCode, nil
}
