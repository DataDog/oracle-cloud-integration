package formatter

import (
	"encoding/base64"
	"encoding/json"
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
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

// streamingEnvelope builds the Service Connector Hub streaming envelope (the
// shape delivered when the source is OCI Streaming) wrapping an inner log
// entry, with the inner JSON base64-encoded in the "value" field.
func streamingEnvelope(inner map[string]any) map[string]any {
	encoded := base64.StdEncoding.EncodeToString(mustJSON(inner))
	return map[string]any{
		"streamPool": "ocid1.streampool.oc1..test",
		"stream":     "ocid1.stream.oc1..test",
		"partition":  "0",
		"key":        "",
		"value":      encoded,
		"offset":     "0",
		"timestamp":  "2024-01-15T10:00:00.000Z",
	}
}

func mustJSON(v any) []byte {
	b, err := json.Marshal(v)
	if err != nil {
		panic(err)
	}
	return b
}

func TestUnwrapStreamingMessages_DecodesEnvelope(t *testing.T) {
	inner := deepCopyMap(singleLogEntry)
	logs := []map[string]any{streamingEnvelope(inner)}

	got, err := UnwrapStreamingMessages(logs)
	require.NoError(t, err)
	require.Len(t, got, 1)
	assert.Equal(t, singleLogEntry, got[0])
}

func TestUnwrapStreamingMessages_PassesPlainEntriesThrough(t *testing.T) {
	// A plain (non-streaming) log entry has a "data" field and no "value"
	// envelope; it must be returned unchanged.
	plain := deepCopyMap(singleLogEntry)
	logs := []map[string]any{plain}

	got, err := UnwrapStreamingMessages(logs)
	require.NoError(t, err)
	require.Len(t, got, 1)
	assert.Equal(t, singleLogEntry, got[0])
}

func TestUnwrapStreamingMessages_MixedBatch(t *testing.T) {
	plain := deepCopyMap(singleLogEntry)
	plain["id"] = "plain"
	streamed := streamingEnvelope(deepCopyMap(singleLogEntry))
	// ensure the inner entry is distinguishable from the plain one
	streamedInner := deepCopyMap(singleLogEntry)
	streamedInner["id"] = "streamed"
	streamed["value"] = base64.StdEncoding.EncodeToString(mustJSON(streamedInner))

	got, err := UnwrapStreamingMessages([]map[string]any{plain, streamed})
	require.NoError(t, err)
	require.Len(t, got, 2)
	assert.Equal(t, "plain", got[0]["id"])
	assert.Equal(t, "streamed", got[1]["id"])
}

func TestUnwrapStreamingMessages_InvalidBase64(t *testing.T) {
	logs := []map[string]any{{"value": "!!!not-base64!!!"}}
	_, err := UnwrapStreamingMessages(logs)
	assert.Error(t, err)
}

func TestUnwrapStreamingMessages_InvalidJSON(t *testing.T) {
	// base64 of "not-json" decodes fine but isn't valid JSON.
	logs := []map[string]any{{"value": base64.StdEncoding.EncodeToString([]byte("not-json"))}}
	_, err := UnwrapStreamingMessages(logs)
	assert.Error(t, err)
}

func TestUnwrapStreamingMessages_EmptyValue(t *testing.T) {
	logs := []map[string]any{{"value": base64.StdEncoding.EncodeToString([]byte(""))}}
	_, err := UnwrapStreamingMessages(logs)
	assert.Error(t, err)
}

// TestProcessLogEntry_StreamingEnvelope verifies the end-to-end fix: a
// streaming envelope, once unwrapped, produces the same LogPayload as the
// inner log entry would have directly.
func TestProcessLogEntry_StreamingEnvelope(t *testing.T) {
	os.Setenv("DATADOG_TAGS", "env:prod,version:1.0")

	inner := deepCopyMap(singleLogEntry)
	unwrapped, err := UnwrapStreamingMessages([]map[string]any{streamingEnvelope(inner)})
	require.NoError(t, err)

	lf, err := NewLogFormatter()
	require.NoError(t, err)

	result := lf.ProcessLogEntry(unwrapped[0])
	assert.Equal(t, expectedSingleLogEntry, result)
}
