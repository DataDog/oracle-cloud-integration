package handler

import (
	"bytes"
	"context"
	"datadog-functions/internal/client"
	"datadog-functions/logs-forwarder/internal/formatter"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"os"
	"testing"
	"time"

	datadog "github.com/DataDog/datadog-api-client-go/v2/api/datadog"
	"github.com/stretchr/testify/assert"
)

// Mock clients for testing
type mockClientBase struct{}

func (c *mockClientBase) PrepareRequest(ctx context.Context, path string, method string, postBody interface{}, headerParams map[string]string, queryParams url.Values, formParams url.Values, fileName *datadog.FormFile) (*http.Request, error) {
	return &http.Request{}, nil
}

type slowMockClient struct {
	mockClientBase
}

func (c *slowMockClient) CallAPI(req *http.Request) (*http.Response, error) {
	select {
	case <-time.After(2 * time.Second):
		return &http.Response{StatusCode: http.StatusAccepted}, nil
	case <-req.Context().Done():
		return nil, req.Context().Err()
	}
}

type batchCountingClient struct {
	mockClientBase
	count *int
}

func (c *batchCountingClient) CallAPI(req *http.Request) (*http.Response, error) {
	*c.count++
	return &http.Response{StatusCode: http.StatusAccepted}, nil
}

type erroringClient struct {
	mockClientBase
}

func (c *erroringClient) CallAPI(req *http.Request) (*http.Response, error) {
	return nil, errors.New("failed to send batch")
}

func TestMyHandler_Success(t *testing.T) {
	// Mock environment variables
	os.Setenv("DD_SITE", "datadoghq.com")
	os.Setenv("API_KEY_SECRET_OCID", "ocid1.apikey.oc1..test")
	os.Setenv("HOME_REGION", "us-ashburn-1")

	// Mock input logs
	logs := []map[string]interface{}{
		{"message": "log1"},
		{"message": "log2"},
		{"message": "log3"},
	}
	logsBytes, _ := json.Marshal(logs)
	in := bytes.NewReader(logsBytes)
	out := &bytes.Buffer{}

	// Mock SendLogsToDatadog function
	originalDatadogClientFunc := datadogClientFunc
	defer func() {
		datadogClientFunc = originalDatadogClientFunc
	}()
	datadogClientFunc = client.NewTestDatadogClientWithSite
	MyHandler(context.Background(), in, out)

	assert.Contains(t, out.String(), `"status":"success"`)
	assert.Contains(t, out.String(), `"message":"Logs sent to Datadog"`)
}

func TestMyHandler_ContextCancellation(t *testing.T) {
	// Create a context that we'll cancel
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Create test logs - reduce the number to make the test more reliable
	logs := make([]map[string]interface{}, 10)
	for i := range logs {
		logs[i] = map[string]interface{}{
			"message": "log1",
			"source":  "test",
			"time":    "2024-01-01T00:00:00Z",
			"type":    "test.log",
			"data":    map[string]interface{}{},
			"oracle":  map[string]interface{}{},
		}
	}
	logsBytes, _ := json.Marshal(logs)
	in := bytes.NewReader(logsBytes)
	out := &bytes.Buffer{}

	// Set a small batch size to ensure multiple batches
	os.Setenv("DD_BATCH_SIZE", "2")
	defer os.Unsetenv("DD_BATCH_SIZE")

	// Mock a slow Datadog client
	originalDatadogClientFunc := datadogClientFunc
	defer func() {
		datadogClientFunc = originalDatadogClientFunc
	}()
	datadogClientFunc = func() (client.DatadogClient, string, error) {
		return client.DatadogClient{Client: &slowMockClient{}}, "datadoghq.com", nil
	}

	// Start handler in a goroutine
	done := make(chan struct{})
	go func() {
		MyHandler(ctx, in, out)
		close(done)
	}()

	// Wait a bit to ensure processing has started
	time.Sleep(100 * time.Millisecond)

	// Cancel context
	cancel()

	// Wait for handler to finish
	select {
	case <-done:
		// Success - handler completed
	case <-time.After(5 * time.Second):
		t.Fatal("handler did not complete within timeout")
	}

	// Verify handler was cancelled
	output := out.String()
	assert.Contains(t, output, `"status":"error"`)
	assert.Contains(t, output, "context canceled")
}

func TestMyHandler_BatchProcessing(t *testing.T) {
	// Set a small batch size
	os.Setenv("DD_BATCH_SIZE", "2")
	defer os.Unsetenv("DD_BATCH_SIZE")

	// Create test logs
	logs := []map[string]interface{}{
		{"message": "log1", "source": "test", "time": "2024-01-01T00:00:00Z", "type": "test.log", "data": map[string]interface{}{}, "oracle": map[string]interface{}{}},
		{"message": "log2", "source": "test", "time": "2024-01-01T00:00:00Z", "type": "test.log", "data": map[string]interface{}{}, "oracle": map[string]interface{}{}},
		{"message": "log3", "source": "test", "time": "2024-01-01T00:00:00Z", "type": "test.log", "data": map[string]interface{}{}, "oracle": map[string]interface{}{}},
	}
	logsBytes, _ := json.Marshal(logs)
	in := bytes.NewReader(logsBytes)
	out := &bytes.Buffer{}

	// Mock client that counts batches
	batchCount := 0
	originalDatadogClientFunc := datadogClientFunc
	defer func() {
		datadogClientFunc = originalDatadogClientFunc
	}()
	datadogClientFunc = func() (client.DatadogClient, string, error) {
		return client.DatadogClient{Client: &batchCountingClient{count: &batchCount}}, "datadoghq.com", nil
	}

	MyHandler(context.Background(), in, out)

	// Should have 2 batches: one with 2 logs, one with 1 log
	assert.Equal(t, 2, batchCount)
	assert.Contains(t, out.String(), `"status":"success"`)
}

func TestMyHandler_ErrorPropagation(t *testing.T) {
	logs := []map[string]interface{}{
		{"message": "log1", "source": "test", "time": "2024-01-01T00:00:00Z", "type": "test.log", "data": map[string]interface{}{}, "oracle": map[string]interface{}{}},
	}
	logsBytes, _ := json.Marshal(logs)
	in := bytes.NewReader(logsBytes)
	out := &bytes.Buffer{}

	// Mock client that returns error
	originalDatadogClientFunc := datadogClientFunc
	defer func() {
		datadogClientFunc = originalDatadogClientFunc
	}()
	datadogClientFunc = func() (client.DatadogClient, string, error) {
		return client.DatadogClient{Client: &erroringClient{}}, "datadoghq.com", nil
	}

	MyHandler(context.Background(), in, out)

	assert.Contains(t, out.String(), `"status":"error"`)
	assert.Contains(t, out.String(), "failed to send batch")
}

func TestFormatLogs(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		want    []formatter.LogPayload
		wantErr bool
	}{
		{
			name:  "valid JSON array",
			input: `[{"message": "log1", "source": "test", "time": "2024-01-01T00:00:00Z", "type": "test.log", "data": {}, "oracle": {}}, {"message": "log2", "source": "test", "time": "2024-01-01T00:00:00Z", "type": "test.log", "data": {}, "oracle": {}}]`,
			want: []formatter.LogPayload{
				{
					OCISource: "test",
					Timestamp: "2024-01-01T00:00:00Z",
					Data:      map[string]interface{}{},
					DDSource:  "oci.logs",
					Service:   "oci",
					Type:      "test.log",
					Oracle:    map[string]interface{}{},
				},
				{
					OCISource: "test",
					Timestamp: "2024-01-01T00:00:00Z",
					Data:      map[string]interface{}{},
					DDSource:  "oci.logs",
					Service:   "oci",
					Type:      "test.log",
					Oracle:    map[string]interface{}{},
				},
			},
			wantErr: false,
		},
		{
			name:  "valid JSON object",
			input: `{"message": "log1", "source": "test", "time": "2024-01-01T00:00:00Z", "type": "test.log", "data": {}, "oracle": {}}`,
			want: []formatter.LogPayload{
				{
					OCISource: "test",
					Timestamp: "2024-01-01T00:00:00Z",
					Data:      map[string]interface{}{},
					DDSource:  "oci.logs",
					Service:   "oci",
					Type:      "test.log",
					Oracle:    map[string]interface{}{},
				},
			},
			wantErr: false,
		},
		{
			name:    "invalid JSON",
			input:   `invalid json`,
			want:    nil,
			wantErr: true,
		},
		{
			name:    "invalid JSON format",
			input:   `123`,
			want:    nil,
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			in := bytes.NewReader([]byte(tt.input))
			formattedLogs := make(chan formatter.LogPayload, 100)

			err := formatLogs(context.Background(), in, formattedLogs)
			if (err != nil) != tt.wantErr {
				t.Errorf("formatLogs() error = %v, wantErr %v", err, tt.wantErr)
				return
			}

			if !tt.wantErr {
				close(formattedLogs)
				var got []formatter.LogPayload
				for log := range formattedLogs {
					got = append(got, log)
				}
				assert.Equal(t, tt.want, got)
			}
		})
	}
}
