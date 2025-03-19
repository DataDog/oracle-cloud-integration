package forwarder

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"

	"oracle-cloud-integration/internal/common"

	"github.com/DataDog/datadog-api-client-go/v2/api/datadog"
)

// SendLogsToDatadog sends log messages to Datadog.
// It prepares the request with appropriate headers and sends the logs to the Datadog API.
//
// Parameters:
//   - client: An instance of DatadogClient containing the API key and site information.
//   - logsMessage: A byte slice containing the log messages to be sent.
//
// Returns:
//   - error: An error if the request preparation or API call fails, or if the response status code is not in the 2xx range.
func SendLogsToDatadog(ctx context.Context, client common.DatadogClient, logsMessage []byte) error {
	status, err := sendLogs(ctx, client, logsMessage)
	if err != nil && status == 403 {
		// Attempt to fetch the API key again in case it has been rotated
		err = client.RefreshAPIKey(ctx)
		if err != nil {
			return err
		}
		_, err = sendLogs(ctx, client, logsMessage)
		return err
	}
	return err
}

func sendLogs(ctx context.Context, client common.DatadogClient, logsMessage []byte) (int, error) {
	apiHeaders := map[string]string{
		"Content-Type": "application/json",
		"DD-API-KEY":   client.ApiKey,
	}
	fmt.Printf("Uncompressed payload size=%d\n", len(logsMessage))

	url := fmt.Sprintf("https://http-intake.logs.%s/api/v2/logs", client.Site)
	req, err := client.Client.PrepareRequest(ctx, url, http.MethodPost, logsMessage, apiHeaders, nil, nil, nil)
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
		return resp.StatusCode, errors.New("failed to send logs to Datadog")
	}
	return resp.StatusCode, nil
}
