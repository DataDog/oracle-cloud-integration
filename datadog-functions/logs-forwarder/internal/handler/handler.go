package handler

import (
	"context"
	"encoding/json"
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
	// defaultBatchSize is the number of logs to accumulate before sending to Datadog
	defaultBatchSize = 1000

	// formatterTimeout is the maximum duration allowed for log formatting operations
	formatterTimeout = 3 * time.Minute
)

// MyHandler is an Oracle Cloud Function that forwards logs to Datadog.
// It coordinates the log processing pipeline:
// - Establishes connection with Datadog using API credentials
// - Processes incoming logs through a formatter
// - Manages concurrent processing with timeouts and error handling
// - Sends formatted logs to Datadog in optimized batches
//
// The function implements graceful shutdown and resource cleanup through context
// cancellation. If any stage of the pipeline fails, it ensures proper error
// reporting and cleanup of goroutines.
//
// Parameters:
//   - ctx: Context for cancellation and timeouts
//   - in: Reader containing the incoming log data in JSON format
//   - out: Writer for the function's response
func MyHandler(ctx context.Context, in io.Reader, out io.Writer) {
	ddclient, site, err := datadogClientFunc()
	if err != nil {
		log.Println(err)
		writeResponse(out, "error", "", err)
		return
	}
	url := fmt.Sprintf("https://http-intake.logs.%s/api/v2/logs", site)

	// Create channels and wait group
	formattedLogs := make(chan formatter.LogPayload, defaultBatchSize)
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
// - Recover from panics and report them as errors
// - Close the formattedLogs channel when done
func startLogsFormatter(ctx context.Context, wg *sync.WaitGroup, in io.Reader, formattedLogs chan<- formatter.LogPayload, errChan chan<- error) {
	wg.Add(1)
	go func() {
		defer func() {
			if r := recover(); r != nil {
				select {
				case errChan <- fmt.Errorf("formatter panic: %v", r):
				case <-ctx.Done():
				}
			}
		}()
		defer wg.Done()

		// Create a context with timeout
		ctx, cancel := context.WithTimeout(ctx, formatterTimeout)
		defer cancel()

		if err := formatLogs(ctx, in, formattedLogs); err != nil {
			select {
			case errChan <- fmt.Errorf("formatter error: %w", err):
			case <-ctx.Done():
				if ctx.Err() == context.DeadlineExceeded {
					errChan <- fmt.Errorf("formatter timed out after %v", formatterTimeout)
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
	// Decode incoming JSON payload - could be either a single log or an array of logs
	var body json.RawMessage
	if err := json.NewDecoder(rawLogs).Decode(&body); err != nil {
		return fmt.Errorf("failed to decode JSON: %w", err)
	}

	// Try to decode as array first
	var logs []map[string]any
	if err := json.Unmarshal(body, &logs); err != nil {
		// Not an array, try single object
		var singleLog map[string]any
		if err := json.Unmarshal(body, &singleLog); err != nil {
			return fmt.Errorf("invalid JSON format: expected object or array of objects: %w", err)
		}
		logs = []map[string]any{singleLog}
	}

	lf, err := formatter.NewLogFormatter()
	if err != nil {
		return fmt.Errorf("failed to create log formatter: %w", err)
	}

	// Process each log entry
	for _, logMap := range logs {
		payload := lf.ProcessLogEntry(logMap)
		select {
		case formattedLogs <- payload:
		case <-ctx.Done():
			return ctx.Err()
		}
	}

	return nil
}

// startLogsSender starts the goroutine that batches logs and manages API workers
func startLogsSender(ctx context.Context, wg *sync.WaitGroup, client client.DatadogClient, url string, formattedLogs <-chan formatter.LogPayload, errChan chan<- error) {
	wg.Add(1)
	go func() {
		defer func() {
			if r := recover(); r != nil {
				select {
				case errChan <- fmt.Errorf("sender panic: %v", r):
				case <-ctx.Done():
				}
			}
		}()
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
		return defaultBatchSize
	}

	batchSize, err := strconv.Atoi(batchSizeStr)
	if err != nil || batchSize <= 0 {
		return defaultBatchSize
	}
	return batchSize
}
