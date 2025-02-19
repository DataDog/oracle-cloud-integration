package client

import (
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"

	datadog "github.com/DataDog/datadog-api-client-go/v2/api/datadog"
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
func SendLogsToDatadog(client DatadogClient, logsMessage []byte) error {
	apiHeaders := map[string]string{
		"Content-Type": "application/json",
		"DD-API-KEY":   client.apiKey,
	}
	fmt.Printf("Uncompressed payload size=%d\n", len(logsMessage))
	if shouldCompressPayload() {
		apiHeaders["Content-Encoding"] = "gzip"
	}

	url := fmt.Sprintf("https://http-intake.logs.%s/api/v2/logs", client.site)
	req, err := client.Client.PrepareRequest(nil, url, http.MethodPost, logsMessage, apiHeaders, nil, nil, nil)
	if err != nil {
		return err
	}

	resp, err := client.Client.CallAPI(req)
	if err != nil {
		return err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		log.Printf("Error: Received non-200 response from Datadog: %d", resp.StatusCode)
		body, err := datadog.ReadBody(resp)
		if err == nil {
			log.Printf("Error response body: %s", string(body))
		}
		return errors.New("failed to send logs to Datadog")
	}
	return nil
}

func shouldCompressPayload() bool {
	return strings.ToLower(os.Getenv("DD_COMPRESS")) == "true"
}
