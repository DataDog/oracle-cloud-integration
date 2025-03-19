package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"oracle-cloud-integration/internal/common"
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
	originalSendFunc := sendLogsFunc
	originalDatadogClientFunc := datadogClientFunc
	defer func() {
		sendLogsFunc = originalSendFunc
		datadogClientFunc = originalDatadogClientFunc
	}()
	sendLogsFunc = func(ctx context.Context, client common.DatadogClient, logsMsg []byte) (int, error) {
		return 202, nil
	}
	datadogClientFunc = common.GetDefaultTestDatadogClient

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
