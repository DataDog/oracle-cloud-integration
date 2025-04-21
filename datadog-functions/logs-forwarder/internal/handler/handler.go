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
	"sync"
	"time"

	"datadog-functions/lib/client"
	"datadog-functions/logs-forwarder/internal/formatter"
)

var datadogClientFunc = client.NewDatadogClientWithSite

const (
	// DefaultBatchSize is the number of logs to accumulate before sending to Datadog
	DefaultBatchSize = 1000

	// FormatterTimeout is the maximum duration allowed for log formatting operations
	FormatterTimeout = 3 * time.Minute
)

// MyHandler processes logs from an input reader and sends them to Datadog in batches.
// It uses a streaming approach with parallel API calls:
// 1. Reads logs one by one from input
// 2. Formats each log using the formatter
// 3. Batches formatted logs
// 4. Sends batches to Datadog using a worker pool
//
// The handler implements timeouts and cancellation:
// - Context cancellation for graceful shutdown
// - Formatter timeout to prevent hanging
// - Error propagation through channels
func MyHandler(ctx context.Context, in io.Reader, out io.Writer) {
	ddclient, site, err := datadogClientFunc()
	if err != nil {
		log.Println(err)
		writeResponse(out, "error", "", err)
		return
	}
	url := fmt.Sprintf("https://http-intake.logs.%s/api/v2/logs", site)

	// Create channels and wait group
	formattedLogs := make(chan formatter.LogPayload, DefaultBatchSize)
	errChan := make(chan error, 1)
	var wg sync.WaitGroup

	// Start the pipeline
	startLogsFormatter(ctx, &wg, in, formattedLogs, errChan)
	startLogsSender(ctx, &wg, ddclient, url, formattedLogs, errChan)

	// Wait for completion and handle errors
	if err := waitForCompletion(&wg, errChan); err != nil {
		log.Println(err)
		writeResponse(out, "error", "", err)
		return
	}

	writeResponse(out, "success", "Logs sent to Datadog", nil)
}

// startLogsFormatter starts a goroutine that reads and formats logs.
// It applies a timeout to prevent the formatter from hanging indefinitely.
// The goroutine will:
// - Read and decode JSON logs from the input
// - Format each log entry
// - Send formatted logs through the channel
// - Handle context cancellation and timeouts
// - Close the formattedLogs channel when done
func startLogsFormatter(ctx context.Context, wg *sync.WaitGroup, in io.Reader, formattedLogs chan<- formatter.LogPayload, errChan chan<- error) {
	wg.Add(1)
	go func() {
		defer wg.Done()

		// Create a context with timeout
		ctx, cancel := context.WithTimeout(ctx, FormatterTimeout)
		defer cancel()

		if err := formatLogs(ctx, in, formattedLogs); err != nil {
			select {
			case errChan <- fmt.Errorf("formatter error: %w", err):
			case <-ctx.Done():
				if ctx.Err() == context.DeadlineExceeded {
					errChan <- fmt.Errorf("formatter timed out after %v", FormatterTimeout)
				} else {
					errChan <- ctx.Err()
				}
			}
			return
		}
		close(formattedLogs)
	}()
}

// formatLogs decodes and formats logs from the input reader.
// It supports both single log entries and arrays of logs.
// The function will stop processing if the context is cancelled.
func formatLogs(ctx context.Context, rawLogs io.Reader, formattedLogs chan<- formatter.LogPayload) error {
	// Decode incoming JSON payload
	var body interface{}
	err := json.NewDecoder(rawLogs).Decode(&body)
	if err != nil {
		return fmt.Errorf("failed to decode JSON: %w", err)
	}

	lf, err := formatter.NewLogFormatter()
	if err != nil {
		return fmt.Errorf("failed to create log formatter: %w", err)
	}

	// Normalize input into a slice of maps
	switch v := body.(type) {
	case []interface{}: // If it's an array, convert to []map[string]interface{}
		for _, item := range v {
			if logMap, ok := item.(map[string]interface{}); ok {
				payload := lf.ProcessLogEntry(logMap)
				select {
				case formattedLogs <- payload:
				case <-ctx.Done():
					return ctx.Err()
				}
			}
		}
	case map[string]interface{}: // If it's a single object, process it directly
		payload := lf.ProcessLogEntry(v)
		select {
		case formattedLogs <- payload:
		case <-ctx.Done():
			return ctx.Err()
		}
	default:
		return errors.New("invalid JSON format: expected object or array of objects")
	}
	return nil
}

// startLogsSender starts the goroutine that batches logs and manages API workers
func startLogsSender(ctx context.Context, wg *sync.WaitGroup, client client.DatadogClient, url string, formattedLogs <-chan formatter.LogPayload, errChan chan<- error) {
	wg.Add(1)
	go func() {
		defer wg.Done()
		if err := batchAndSendLogs(ctx, client, url, formattedLogs); err != nil {
			select {
			case errChan <- err:
			case <-ctx.Done():
			}
			return
		}
	}()
}

// batchAndSendLogs reads formatted logs from channel, batches them, and sends to Datadog
func batchAndSendLogs(ctx context.Context, client client.DatadogClient, url string, formattedLogs <-chan formatter.LogPayload) error {
	batchSize := getBatchSize()
	batch := make([]formatter.LogPayload, 0, batchSize)

	// Process logs and create batches
	for logData := range formattedLogs {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			batch = append(batch, logData)

			// Send batch if full
			if len(batch) >= batchSize {
				if err := sendBatch(ctx, client, url, batch); err != nil {
					return fmt.Errorf("failed to send batch to Datadog: %w", err)
				}
				batch = batch[:0]
			}
		}
	}

	// Send any remaining logs
	if len(batch) > 0 {
		if err := sendBatch(ctx, client, url, batch); err != nil {
			return fmt.Errorf("failed to send final batch to Datadog: %w", err)
		}
	}

	return nil
}

func sendBatch(ctx context.Context, client client.DatadogClient, url string, batch []formatter.LogPayload) error {
	jsonData, err := json.Marshal(batch)
	if err != nil {
		return fmt.Errorf("failed to marshal batch: %w", err)
	}

	if err := client.SendMessageToDatadog(ctx, jsonData, url); err != nil {
		return fmt.Errorf("failed to send batch to Datadog: %w", err)
	}
	return nil
}

// waitForCompletion waits for all goroutines to finish and returns any error
func waitForCompletion(wg *sync.WaitGroup, errChan chan error) error {
	// Start a goroutine to close errChan when all work is done
	go func() {
		wg.Wait()
		close(errChan)
	}()

	// Wait for error or completion
	return <-errChan
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
