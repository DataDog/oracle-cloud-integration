package formatter

import (
	"encoding/json"
	"os"
	"strings"
)

const DD_SERVICE = "oci"
const DD_SOURCE = "oci.logs"

// ProcessedLog represents the transformed log format.
type logPayload struct {
	Source    string                 `json:"source,omitempty"`
	Timestamp string                 `json:"timestamp,omitempty"`
	Data      map[string]interface{} `json:"data,omitempty"`
	DDSource  string                 `json:"ddsource,omitempty"`
	Service   string                 `json:"service"`
	Type      string                 `json:"type,omitempty"`
	Oracle    map[string]interface{} `json:"oracle,omitempty"`
	DDTags    string                 `json:"ddtags,omitempty"`
}

// GenerateLogsMsg generates a JSON-encoded byte slice from a slice of log entries.
// It applies redaction to each log entry based on an exclusion list and adds tags to each log payload.
// Parameters:
// - logs: A slice of maps where each map represents a log entry with string keys and interface{} values.
// Returns:
// - A byte slice containing the JSON-encoded log payloads.
// - An error if any occurs during the process of getting the exclusion list or marshaling the JSON data.
func GenerateLogsMsg(logs []map[string]interface{}) ([]byte, error) {
	excludeSet, err := getExcludeList()
	if err != nil {
		return nil, err
	}
	tags := getTags()
	logPayloads := make([]logPayload, len(logs))
	for i, log := range logs {
		applyRedaction(log, excludeSet)
		logPayload := formatLog(log)
		logPayload.DDTags = tags
		logPayloads[i] = logPayload
	}
	jsonData, err := json.Marshal(logPayloads)
	if err != nil {
		return nil, err
	}
	return jsonData, nil
}

// getTags validates the DATADOG_TAGS format: "key:value,key2:value2"
func getTags() string {
	tags := os.Getenv("DATADOG_TAGS")
	if tags == "" {
		return ""
	}

	tagPairs := strings.Split(tags, ",")
	for _, tagPair := range tagPairs {
		if strings.Count(tagPair, ":") != 1 {
			return ""
		}
	}

	return tags
}

func formatLog(log map[string]interface{}) logPayload {
	return logPayload{
		Source:    getFieldValue(log, "source", false).(string),
		Timestamp: getFieldValue(log, "time", false).(string),
		Data:      getFieldValue(log, "data", true).(map[string]interface{}),
		DDSource:  getSource(log),
		Service:   DD_SERVICE,
		Type:      getFieldValue(log, "type", false).(string),
		Oracle:    getFieldValue(log, "oracle", true).(map[string]interface{}),
	}
}

func getFieldValue(log map[string]interface{}, field string, isMap bool) interface{} {
	if isMap {
		if val, ok := log[field].(map[string]interface{}); ok {
			return val
		}
		return make(map[string]interface{})
	} else {
		if val, ok := log[field].(string); ok {
			return val
		}
		return ""
	}
}

func getSource(log map[string]interface{}) string {
	oracle := getFieldValue(log, "oracle", true).(map[string]interface{})
	if loggroupID, exists := oracle["loggroupid"].(string); exists && loggroupID == "_Audit" {
		return "oci.audit"
	}

	logtype, ok := log["type"].(string)
	if ok && logtype != "" {
		splitLogType := strings.Split(logtype, ".")
		if len(splitLogType) >= 3 {
			return "oci." + splitLogType[2]
		}
	}
	return DD_SOURCE
}
