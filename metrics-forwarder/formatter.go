package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"

	fdk "github.com/fnproject/fdk-go"
)

var outputMessageVersion = "v1.0"

type Header struct {
	TenancyOCID     string `json:"tenancy_ocid"`
	SourceFnAppOCID string `json:"source_fn_app_ocid"`
	SourceFnAppName string `json:"source_fn_app_name"`
	SourceFnOCID    string `json:"source_fn_ocid"`
	SourceFnName    string `json:"source_fn_name"`
	SourceFnCallID  string `json:"source_fn_call_id"`
}

type Payload struct {
	Headers Header `json:"headers"`
	Body    string `json:"body"`
}

type MetricsMessage struct {
	Version string  `json:"version"`
	Payload Payload `json:"payload"`
}

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

	header := Header{
		TenancyOCID:     tenancyOCID,
		SourceFnAppOCID: md.AppID(),
		SourceFnAppName: md.AppName(),
		SourceFnOCID:    md.FnID(),
		SourceFnName:    md.FnName(),
		SourceFnCallID:  md.CallID(),
	}

	payload := Payload{
		Headers: header,
		Body:    serializedMetricData,
	}

	message := MetricsMessage{
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
	return os.Getenv("DETAILED_LOGGING_ENABLED") == "true"
}
