package formatter

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

// GenerateMetricsMsg generates a metrics message in JSON format.
//
// This function extracts function metadata from the provided context, constructs
// a header and payload, and then marshals them into a JSON message.
//
// Parameters:
//   - ctx: The context from which to extract function metadata.
//   - serializedMetricData: The serialized metric data to include in the message body.
//   - tenancyOCID: The OCID of the tenancy.
//
// Returns:
//   - []byte: The generated JSON message.
//   - error: An error if the message generation fails.
func GenerateMetricsMsg(ctx context.Context, serializedMetricData string, tenancyOCID string) ([]byte, error) {
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
