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

func MyHandler(ctx context.Context, in io.Reader, out io.Writer) {
	site, apiKey, err := readEnvVars()
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
		err = processLogs(logs[i:end], site, apiKey)
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

func processLogs(logs []map[string]interface{}, site, apiKey string) error {
	logsMsg, err := formatter.GenerateLogsMsg(logs)
	if err != nil {
		return err
	}
	err = sendLogsFunc(client.CreateDatadogClient(site, apiKey), logsMsg)
	if err != nil {
		return err
	}
	return nil
}

func readEnvVars() (string, string, error) {
	site := os.Getenv("DD_SITE")
	apiKey := os.Getenv("DD_API_KEY")
	if site == "" || apiKey == "" {
		return "", "", errors.New("missing one of the required environment variables: DD_SITE, DD_API_KEY")
	}
	return site, apiKey, nil
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
