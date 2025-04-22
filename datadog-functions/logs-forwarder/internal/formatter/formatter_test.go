package formatter

import (
	"encoding/json"
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
)

var singleLogEntry = map[string]any{
	"data": map[string]any{
		"level":       "INFO",
		"message":     "Hello World",
		"messageType": "CONNECTOR_RUN_COMPLETED",
	},
	"id": "6b9819cf-d004-4dbc-9978-b713e743ad08",
	"oracle": map[string]any{
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

var expectedSingleLogEntry = LogPayload{
	OCISource: "Log_Connector",
	Timestamp: "2024-09-29T18:10:45.130Z",
	Data: map[string]any{
		"level":       "INFO",
		"message":     "Hello World",
		"messageType": "CONNECTOR_RUN_COMPLETED",
	},
	DDSource: "oci.sch",
	Service:  "oci",
	Type:     "com.oraclecloud.sch.serviceconnector.runlog",
	Oracle: map[string]any{
		"compartmentid": "comp",
		"ingestedtime":  "2024-09-29T18:10:45.130Z",
		"loggroupid":    "lgid",
		"logid":         "lid",
		"resourceid":    "rid",
		"tenantid":      "tid",
	},
	DDTags: "env:prod,version:1.0",
}

func deepCopyMap(src map[string]any) map[string]any {
	bytes, _ := json.Marshal(src)
	var dst map[string]any
	json.Unmarshal(bytes, &dst)
	return dst
}

func deepCopyStruct(src LogPayload) LogPayload {
	bytes, _ := json.Marshal(src)
	var dst LogPayload
	json.Unmarshal(bytes, &dst)
	return dst
}

func TestProcessLogEntry(t *testing.T) {
	// Set up environment variable for tags
	os.Setenv("DATADOG_TAGS", "env:prod,version:1.0")

	tests := []struct {
		name     string
		logs     []map[string]any
		expected []LogPayload
	}{
		{
			name:     "Single log entry",
			logs:     []map[string]any{singleLogEntry},
			expected: []LogPayload{expectedSingleLogEntry},
		},
		{
			name: "Log type = audit",
			logs: []map[string]any{
				func() map[string]any {
					entry := deepCopyMap(singleLogEntry)
					entry["oracle"].(map[string]any)["loggroupid"] = AUDIT_LOGGROUP_ID
					return entry
				}(),
			},
			expected: []LogPayload{
				func() LogPayload {
					entry := deepCopyStruct(expectedSingleLogEntry)
					entry.DDSource = "oci.audit"
					entry.Oracle["loggroupid"] = AUDIT_LOGGROUP_ID
					return entry
				}(),
			},
		},
	}

	lf, err := NewLogFormatter()
	assert.NoError(t, err)

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var results []LogPayload
			for _, log := range tt.logs {
				result := lf.ProcessLogEntry(log)
				results = append(results, result)
			}
			assert.Equal(t, tt.expected, results)
		})
	}
}
