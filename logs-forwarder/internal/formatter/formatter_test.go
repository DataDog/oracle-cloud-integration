package formatter

import (
	"encoding/json"
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
)

var singleLogEntry = map[string]interface{}{
	"data": map[string]interface{}{
		"level":       "INFO",
		"message":     "Hello World",
		"messageType": "CONNECTOR_RUN_COMPLETED",
	},
	"id": "6b9819cf-d004-4dbc-9978-b713e743ad08",
	"oracle": map[string]interface{}{
		"compartmentid": "comp",
		"ingestedtime":  "2024-09-29T18:10:45.130Z",
		"loggroupid":    "lgid",
		"logid":         "lid",
		"resourceid":    "rid",
		"tenantid":      "tid",
	},
	"source":      "Log_Connector",
	"specversion": "1.0",
	"time":        "2024-09-29T18:10:45.130Z",
	"type":        "com.oraclecloud.sch.serviceconnector.runlog",
}

var expectedSingleLogEntry = logPayload{
	OCISource: "Log_Connector",
	Timestamp: "2024-09-29T18:10:45.130Z",
	Data: map[string]interface{}{
		"level":       "INFO",
		"message":     "Hello World",
		"messageType": "CONNECTOR_RUN_COMPLETED",
	},
	DDSource: "oci.sch",
	Service:  "oci",
	Type:     "com.oraclecloud.sch.serviceconnector.runlog",
	Oracle: map[string]interface{}{
		"compartmentid": "comp",
		"ingestedtime":  "2024-09-29T18:10:45.130Z",
		"loggroupid":    "lgid",
		"logid":         "lid",
		"resourceid":    "rid",
		"tenantid":      "tid",
	},
	DDTags: "env:prod,version:1.0",
}

func deepCopyMap(src map[string]interface{}) map[string]interface{} {
	bytes, _ := json.Marshal(src)
	var dst map[string]interface{}
	json.Unmarshal(bytes, &dst)
	return dst
}

func deepCopyStruct(src logPayload) logPayload {
	bytes, _ := json.Marshal(src)
	var dst logPayload
	json.Unmarshal(bytes, &dst)
	return dst
}

func TestGenerateLogsMsg(t *testing.T) {
	// Set up environment variable for tags
	os.Setenv("DATADOG_TAGS", "env:prod,version:1.0")

	tests := []struct {
		name     string
		logs     []map[string]interface{}
		expected []logPayload
	}{
		{
			name:     "Single log entry",
			logs:     []map[string]interface{}{singleLogEntry},
			expected: []logPayload{expectedSingleLogEntry},
		},
		{
			name: "Log type = audit",
			logs: []map[string]interface{}{
				func() map[string]interface{} {
					entry := deepCopyMap(singleLogEntry)
					entry["oracle"].(map[string]interface{})["loggroupid"] = "_Audit"
					return entry
				}(),
			},
			expected: []logPayload{
				func() logPayload {
					entry := deepCopyStruct(expectedSingleLogEntry)
					entry.DDSource = "oci.audit"
					entry.Oracle["loggroupid"] = "_Audit"
					return entry
				}(),
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := GenerateLogsMsg(tt.logs)
			assert.NoError(t, err)

			var logPayloads []logPayload
			err = json.Unmarshal(result, &logPayloads)
			assert.NoError(t, err)

			assert.Equal(t, tt.expected, logPayloads)
		})
	}
}
