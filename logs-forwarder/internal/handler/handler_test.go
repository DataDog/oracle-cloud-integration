package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"logs-forwarder/internal/client"
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestMyHandler_Success(t *testing.T) {
	// Mock environment variables
	os.Setenv("DD_SITE", "datadoghq.com")
	os.Setenv("DD_API_KEY", "test-api-key")
	os.Setenv("DD_BATCH_SIZE", "2")

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
	originalSendFunc := sendLogsFunc
	defer func() { sendLogsFunc = originalSendFunc }()
	sendLogsFunc = func(client client.DatadogClient, logsMsg []byte) error {
		return nil
	}

	MyHandler(context.Background(), in, out)

	assert.Contains(t, out.String(), `"status":"success"`)
	assert.Contains(t, out.String(), `"message":"Logs sent to Datadog"`)
}

func TestGetSerializedLogsData(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		want    []map[string]interface{}
		wantErr bool
	}{
		{
			name:    "valid JSON array",
			input:   `[{"message": "log1"}, {"message": "log2"}]`,
			want:    []map[string]interface{}{{"message": "log1"}, {"message": "log2"}},
			wantErr: false,
		},
		{
			name:    "valid JSON object",
			input:   `{"message": "log1"}`,
			want:    []map[string]interface{}{{"message": "log1"}},
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
			got, err := getSerializedLogsData(in)
			if (err != nil) != tt.wantErr {
				t.Errorf("getSerializedLogsData() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			assert.Equal(t, tt.want, got)
		})
	}
}
