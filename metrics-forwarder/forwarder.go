package main

import (
	"bytes"
	"compress/gzip"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
)

var httpClient = &http.Client{}

type HTTPClient interface {
	Do(req *http.Request) (*http.Response, error)
}

func sendMetricsToDatadog(metricsMessage []byte, client HTTPClient) error {
	endpoint := os.Getenv("DD_INTAKE_HOST")
	apiKey := os.Getenv("DD_API_KEY")

	if endpoint == "" || apiKey == "" {
		return errors.New("missing one of the required environment variables: DD_INTAKE_HOST, DD_API_KEY")
	}

	url := fmt.Sprintf("https://%s/api/v2/ocimetrics", endpoint)
	apiHeaders := map[string]string{
		"Content-Type": "application/json",
		"DD-API-KEY":   apiKey,
	}

	if shouldCompressPayload() {
		compressedPayload, err := compressPayload(metricsMessage)
		if err != nil {
			log.Printf("Error compressing payload: %v", err)
		} else {
			fmt.Printf("Uncompressed payload size=%d\n", len(metricsMessage))
			metricsMessage = compressedPayload
			apiHeaders["Content-Encoding"] = "Gzip"
		}
	}

	// Send the metrics data
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(metricsMessage))
	if err != nil {
		return err
	}

	for key, value := range apiHeaders {
		req.Header.Set(key, value)
	}

	fmt.Printf("Sending payload size=%d encoding=%s\n", len(metricsMessage), apiHeaders["Content-Encoding"])

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	// Check response status
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		log.Printf("Error: Received non-200 response from Datadog: %d", resp.StatusCode)
		return errors.New("failed to send metrics to Datadog")
	}
	return nil
}

func shouldCompressPayload() bool {
	return os.Getenv("DD_COMPRESS") == "true"
}

func compressPayload(payload []byte) ([]byte, error) {
	var buf bytes.Buffer
	gzipWriter := gzip.NewWriter(&buf)
	_, err := gzipWriter.Write(payload)
	if err != nil {
		return nil, err
	}
	if err := gzipWriter.Close(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}
