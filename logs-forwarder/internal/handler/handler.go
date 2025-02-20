package handler

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"strconv"

	"logs-forwarder/internal/client"
	"logs-forwarder/internal/formatter"
)

var sendLogsFunc = client.SendLogsToDatadog

const DefaultBatchSize = 1000

// MyHandler processes logs from an input reader and sends them to Datadog in batches.
// It reads necessary environment variables, deserializes the logs, and processes them in batches.
// If any error occurs during the process, it writes an error response to the output writer.
//
// Parameters:
//   - ctx: The context for the handler.
//   - in: The input reader containing serialized logs data.
//   - out: The output writer to write responses.
//
// The function performs the following steps:
//  1. Reads environment variables for site and apiKey.
//  2. Deserializes the logs data from the input reader.
//  3. Processes the logs in batches, sending them to Datadog.
//  4. Writes a success response if all logs are processed successfully, or an error response if any step fails.
func MyHandler(ctx context.Context, in io.Reader, out io.Writer) {
	client, err := createDatadogClient()
	if err != nil {
		log.Println(err)
		writeResponse(out, "error", "", err)
		return
	}

	logs, err := getSerializedLogsData(in)
	if err != nil {
		log.Println(err)
		writeResponse(out, "error", "", err)
		return
	}

	batchSize := getBatchSize()
	fmt.Printf("Received %d logs to process with a batch size of %d\n", len(logs), batchSize)

	for i := 0; i < len(logs); i += batchSize {
		end := i + batchSize
		if end > len(logs) {
			end = len(logs)
		}
		err = processLogs(client, logs[i:end])
		if err != nil {
			log.Printf("Error processing logs in batch %d: %v", i/batchSize+1, err)
			writeResponse(out, "error", "", err)
			return
		}
	}
	writeResponse(out, "success", "Logs sent to Datadog", nil)
}

func getSerializedLogsData(rawLogs io.Reader) ([]map[string]interface{}, error) {
	// Decode incoming JSON payload
	var body interface{}
	err := json.NewDecoder(rawLogs).Decode(&body)
	if err != nil {
		return nil, err
	}

	// Normalize input into a slice of maps
	var logs []map[string]interface{}
	switch v := body.(type) {
	case []interface{}: // If it's an array, convert to []map[string]interface{}
		for _, item := range v {
			if logMap, ok := item.(map[string]interface{}); ok {
				logs = append(logs, logMap)
			}
		}
	case map[string]interface{}: // If it's a single object, wrap in an array
		logs = append(logs, v)
	default:
		return nil, errors.New("invalid JSON format")
	}
	return logs, nil
}

func processLogs(client client.DatadogClient, logs []map[string]interface{}) error {
	logsMsg, err := formatter.GenerateLogsMsg(logs)
	if err != nil {
		return err
	}
	err = sendLogsFunc(client, logsMsg)
	if err != nil {
		return err
	}
	return nil
}

func createDatadogClient() (client.DatadogClient, error) {
	site := os.Getenv("DD_SITE")
	apiKey := os.Getenv("DD_API_KEY")
	if site == "" || apiKey == "" {
		return client.DatadogClient{}, errors.New("missing one of the required environment variables: DD_SITE, DD_API_KEY")
	}
	return client.CreateDatadogClient(site, apiKey), nil
}

func getBatchSize() int {
	batchSizeStr := os.Getenv("DD_BATCH_SIZE")
	if batchSizeStr == "" {
		return DefaultBatchSize
	}

	batchSize, err := strconv.Atoi(batchSizeStr)
	if err != nil || batchSize <= 0 {
		return DefaultBatchSize
	}
	return batchSize
}
