package main

import (
	"bytes"
	"context"
	"io"
	"log"

	fdk "github.com/fnproject/fdk-go"
)

var sendMetricsFunc = sendMetricsToDatadog

func main() {
	fdk.Handle(fdk.HandlerFunc(myHandler))
}

func myHandler(ctx context.Context, in io.Reader, out io.Writer) {
	// 1. Read metrics data
	serializedMetricData, err := getSerializedMetricData(in)
	if err != nil {
		log.Printf("Error reading metric data: %v", err)
		writeResponse(out, "error", "", err)
		return
	}

	// 2. Create structured metrics message
	metricsMsg, err := generateMetricsMsg(ctx, serializedMetricData)
	if err != nil {
		log.Printf("Error serializing metrics message: %v", err)
		writeResponse(out, "error", "", err)
		return
	}

	// 3. Send message to Datadog
	err = sendMetricsFunc(metricsMsg, httpClient)
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
