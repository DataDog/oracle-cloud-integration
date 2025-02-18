package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"

	fdk "github.com/fnproject/fdk-go"
)

var outputMessageVersion = "v1.0"

type header struct {
	TenancyOCID     string `json:"tenancy_ocid"`
	SourceFnAppOCID string `json:"source_fn_app_ocid"`
	SourceFnAppName string `json:"source_fn_app_name"`
	SourceFnOCID    string `json:"source_fn_ocid"`
	SourceFnName    string `json:"source_fn_name"`
	SourceFnCallID  string `json:"source_fn_call_id"`
}

type payload struct {
	Headers header `json:"headers"`
	Body    string `json:"body"`
}

type metricsMessage struct {
	Version string  `json:"version"`
	Payload payload `json:"payload"`
}

// generateMetricsMsg generates a metrics message in JSON format.
// It retrieves the tenancy OCID from the environment variables and extracts function metadata from the Fn context.
// The function constructs a message with the retrieved metadata and serialized metric data, and returns the JSON-encoded message.
//
// Parameters:
//   - ctx: The context from which to retrieve the Fn context metadata.
//   - serializedMetricData: The serialized metric data to include in the message body.
//
// Returns:
//   - []byte: The JSON-encoded metrics message.
//   - error: An error if any occurs during the process, such as missing environment variables or JSON marshalling errors.
func generateMetricsMsg(ctx context.Context, serializedMetricData string) ([]byte, error) {
	tenancyOCID := os.Getenv("TENANCY_OCID")
	if tenancyOCID == "" {
		return nil, errors.New("missing environment variable: TENANCY_OCID")
	}

	// Extract function metadata from Fn Context
	md, ok := fdk.GetContext(ctx).(fdk.Context)
	if !ok {
		return nil, errors.New("failed to retrieve Fn context metadata")
	}

	header := header{
		TenancyOCID:     tenancyOCID,
		SourceFnAppOCID: md.AppID(),
		SourceFnAppName: md.AppName(),
		SourceFnOCID:    md.FnID(),
		SourceFnName:    md.FnName(),
		SourceFnCallID:  md.CallID(),
	}

	payload := payload{
		Headers: header,
		Body:    serializedMetricData,
	}

	message := metricsMessage{
		Version: outputMessageVersion,
		Payload: payload,
	}

	jsonData, err := json.Marshal(message)
	if err != nil {
		return nil, err
	}

	if isDetailedLoggingEnabled() {
		fmt.Println("Metric payload =", string(jsonData))
	}
	return jsonData, nil
}

func isDetailedLoggingEnabled() bool {
	return strings.ToLower(os.Getenv("DETAILED_LOGGING_ENABLED")) == "true"
}
