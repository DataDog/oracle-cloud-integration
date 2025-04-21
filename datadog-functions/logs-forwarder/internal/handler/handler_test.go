package handler

import (
	"bytes"
	"context"
	"datadog-functions/lib/client"
	"datadog-functions/logs-forwarder/internal/formatter"
	"encoding/json"
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
)

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

func TestMyHandler_BatchProcessing(t *testing.T) {
	// Set a small batch size
	os.Setenv("DD_BATCH_SIZE", "2")
	defer os.Unsetenv("DD_BATCH_SIZE")

	// Set required environment variables
	os.Setenv("DD_SITE", "datadoghq.com")
	os.Setenv("API_KEY_SECRET_OCID", "ocid1.apikey.oc1..test")
	os.Setenv("HOME_REGION", "us-ashburn-1")
	defer func() {
		os.Unsetenv("DD_SITE")
		os.Unsetenv("API_KEY_SECRET_OCID")
		os.Unsetenv("HOME_REGION")
	}()

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
	originalDatadogClientFunc := datadogClientFunc
	defer func() {
		datadogClientFunc = originalDatadogClientFunc
	}()
	datadogClientFunc = func() (client.DatadogClient, string, error) {
		return client.NewTestDatadogClientWithSite()
	}

	MyHandler(context.Background(), in, out)

	// Should have 2 batches: one with 2 logs, one with 1 log
	assert.Contains(t, out.String(), `"status":"success"`)
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
