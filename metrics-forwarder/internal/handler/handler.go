package handler

import (
	"bytes"
	"context"
	"errors"
	"io"
	"log"
	"os"

	"metrics-forwarder/internal/client"
	"metrics-forwarder/internal/formatter"
)

var sendMetricsFunc = client.SendMetricsToDatadog

// MyHandler processes incoming metrics data, formats it, and sends it to Datadog.
// It performs the following steps:
// 1. Reads metrics data from the input reader.
// 2. Reads necessary environment variables such as tenancy OCID, site, and Datadog API key.
// 3. Generates a metrics message using the serialized metric data and tenancy OCID.
// 4. Sends the generated metrics message to Datadog.
// 5. Writes a response to the output writer indicating success or failure.
//
// Parameters:
// - ctx: The context for controlling cancellation and deadlines.
// - in: An io.Reader from which the metrics data is read.
// - out: An io.Writer to which the response is written.
func MyHandler(ctx context.Context, in io.Reader, out io.Writer) {
	// 1. Read metrics data
	serializedMetricData, err := getSerializedMetricData(in)
	if err != nil {
		log.Printf("Error reading metric data: %v", err)
		writeResponse(out, "error", "", err)
		return
	}

	// 2. Read tenancy OCID, site and datadog API key
	client, tenancyOCID, err := newDatadogClientWithTenancy()
	if err != nil {
		log.Println(err)
		writeResponse(out, "error", "", err)
		return
	}

	// 3. Generate metrics message
	metricsMsg, err := formatter.GenerateMetricsMsg(ctx, serializedMetricData, tenancyOCID)
	if err != nil {
		log.Printf("Error serializing metrics message: %v", err)
		writeResponse(out, "error", "", err)
		return
	}

	// 4. Send message to Datadog
	err = sendMetricsFunc(client, metricsMsg)
	if err != nil {
		log.Printf("Error sending metrics to Datadog: %v", err)
		writeResponse(out, "error", "", err)
		return
	}

	// 4. Return response
	writeResponse(out, "success", "Metrics sent to Datadog", nil)
}

func getSerializedMetricData(rawMetrics io.Reader) (string, error) {
	buf := new(bytes.Buffer)
	_, err := buf.ReadFrom(rawMetrics)
	if err != nil {
		return "", err
	}
	return buf.String(), nil
}

func newDatadogClientWithTenancy() (client.DatadogClient, string, error) {
	tenancyOCID := os.Getenv("TENANCY_OCID")
	site := os.Getenv("DD_SITE")
	apiKey := os.Getenv("DD_API_KEY")
	if tenancyOCID == "" || site == "" || apiKey == "" {
		return client.DatadogClient{}, "", errors.New("missing one of the required environment variables: TENANCY_OCID, DD_SITE, DD_API_KEY")
	}
	return client.NewDatadogClient(site, apiKey), tenancyOCID, nil
}
