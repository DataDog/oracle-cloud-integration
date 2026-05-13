package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"strings"

	"datadog-functions/lib/client"
	"datadog-functions/metrics-forwarder/internal/formatter"

	fdk "github.com/fnproject/fdk-go"
)

var datadogClientFunc = client.NewDatadogClientWithTenancyAndSite

const (
	dlqPrefixMetrics       = "metrics"
	dlqBucketNameMetrics   = "dd-metrics-backfill"
	replayFromDLQHeader    = "Replay-From-DLQ"
)

// metricsDLQ is the subset of DLQ operations used by this handler.
type metricsDLQ interface {
	WriteWithGeneratedKey(ctx context.Context, prefix string, payload []byte) (string, error)
	ListKeysPage(ctx context.Context, prefix string, start *string, limit int) ([]string, *string, error)
	Read(ctx context.Context, key string) ([]byte, error)
	Delete(ctx context.Context, key string) error
}

// getMetricsDLQ resolves a DLQ client from env. Overridden in tests.
var getMetricsDLQ = func(namespace, bucketName, region string) (metricsDLQ, error) {
	c, err := client.NewDLQClient(namespace, bucketName, region)
	if err != nil {
		return nil, err
	}
	if c == nil {
		return nil, nil
	}
	return c, nil
}

// MyHandler processes metrics: normal invocations write formatted payloads to the DLQ bucket only.
// Replay mode (body {"replayFromDlq":true} or header Replay-From-DLQ: true) lists objects under
// the metrics prefix, POSTs each payload to Datadog, then deletes the object on success.
func MyHandler(ctx context.Context, in io.Reader, out io.Writer) {
	body, err := io.ReadAll(in)
	if err != nil {
		log.Printf("Error reading input: %v", err)
		writeResponse(out, "error", "", err)
		return
	}

	if isReplayFromHeader(ctx) || isReplayFromBody(body) {
		handleReplayFromDLQ(ctx, out)
		return
	}

	_, tenancyOCID, _, err := datadogClientFunc()
	if err != nil {
		log.Println(err)
		writeResponse(out, "error", "", err)
		return
	}

	metricsMsg, err := formatter.GenerateMetricsMsg(ctx, string(body), tenancyOCID)
	if err != nil {
		log.Printf("Error serializing metrics message: %v", err)
		writeResponse(out, "error", "", err)
		return
	}

	namespace, region := getDLQParamsFromEnv()
	dlq, err := getMetricsDLQ(namespace, dlqBucketNameMetrics, region)
	if err != nil {
		log.Printf("DLQ client init failed: %v", err)
		writeResponse(out, "error", "", err)
		return
	}
	if dlq == nil {
		writeResponse(out, "error", "", fmt.Errorf("DLQ requires DLQ_BUCKET_NAMESPACE and DLQ_BUCKET_REGION"))
		return
	}

	if _, err := dlq.WriteWithGeneratedKey(ctx, dlqPrefixMetrics+"/", metricsMsg); err != nil {
		log.Printf("DLQ write failed: %v", err)
		writeResponse(out, "error", "", err)
		return
	}

	writeResponse(out, "success", "Metrics written to DLQ (send to Datadog only via replay)", nil)
}

func isReplayFromHeader(ctx context.Context) bool {
	fnCtx := fdk.GetContext(ctx)
	if fnCtx == nil || fnCtx.Header() == nil {
		return false
	}
	v := strings.TrimSpace(fnCtx.Header().Get(replayFromDLQHeader))
	return strings.EqualFold(v, "true") || v == "1"
}

func isReplayFromBody(body []byte) bool {
	var v struct {
		ReplayFromDlq *bool `json:"replayFromDlq"`
	}
	if err := json.Unmarshal(body, &v); err != nil {
		return false
	}
	return v.ReplayFromDlq != nil && *v.ReplayFromDlq
}

func getDLQParamsFromEnv() (namespace, region string) {
	return os.Getenv("DLQ_BUCKET_NAMESPACE"), os.Getenv("DLQ_BUCKET_REGION")
}

func handleReplayFromDLQ(ctx context.Context, out io.Writer) {
	namespace, region := getDLQParamsFromEnv()
	dlq, err := getMetricsDLQ(namespace, dlqBucketNameMetrics, region)
	if err != nil {
		log.Printf("DLQ client init failed: %v", err)
		writeResponse(out, "error", "", err)
		return
	}
	if dlq == nil {
		writeResponse(out, "error", "", fmt.Errorf("replay requires DLQ_BUCKET_NAMESPACE and DLQ_BUCKET_REGION"))
		return
	}

	ddclient, _, site, err := datadogClientFunc()
	if err != nil {
		log.Println(err)
		writeResponse(out, "error", "", err)
		return
	}
	url := fmt.Sprintf("https://ocimetrics-intake.%s/api/v2/ocimetrics", site)

	prefix := dlqPrefixMetrics + "/"
	sent := 0
	var start *string
	for {
		keys, nextStart, err := dlq.ListKeysPage(ctx, prefix, start, 0)
		if err != nil {
			log.Printf("DLQ list failed: %v", err)
			writeResponse(out, "error", "", err)
			return
		}
		for _, key := range keys {
			payload, err := dlq.Read(ctx, key)
			if err != nil {
				log.Printf("DLQ read %q failed: %v", key, err)
				continue
			}
			if err := ddclient.SendMessageToDatadog(ctx, payload, url); err != nil {
				log.Printf("Replay send %q failed: %v", key, err)
				continue
			}
			if err := dlq.Delete(ctx, key); err != nil {
				log.Printf("Replay delete %q failed (non-fatal): %v", key, err)
			}
			sent++
		}
		if nextStart == nil {
			break
		}
		start = nextStart
	}

	writeResponse(out, "success", fmt.Sprintf("Replay sent %d metrics batches from DLQ to Datadog", sent), nil)
}

func getSerializedMetricData(rawMetrics io.Reader) (string, error) {
	buf := new(bytes.Buffer)
	_, err := buf.ReadFrom(rawMetrics)
	if err != nil {
		return "", err
	}
	return buf.String(), nil
}
