package formatter

import (
	"os"
	"strings"
)

const DD_SERVICE = "oci"
const DD_SOURCE = "oci.logs"
const AUDIT_LOGGROUP_ID = "_Audit"

// LogPayload represents the transformed log format.
type LogPayload struct {
	OCISource string         `json:"ocisource,omitempty"`
	Timestamp string         `json:"timestamp,omitempty"`
	Data      map[string]any `json:"data,omitempty"`
	DDSource  string         `json:"ddsource,omitempty"`
	Service   string         `json:"service"`
	Type      string         `json:"type,omitempty"`
	Oracle    map[string]any `json:"oracle,omitempty"`
	DDTags    string         `json:"ddtags,omitempty"`
}

type LogFormatter struct {
	Service string
	Tags    string
	Exclude map[string]struct{}
}

func NewLogFormatter() (*LogFormatter, error) {
	excludeSet, err := getExcludeList()
	if err != nil {
		return nil, err
	}
	return &LogFormatter{
		Service: DD_SERVICE,
		Tags:    getTags(),
		Exclude: excludeSet,
	}, nil
}

// ProcessLogEntry processes a single log entry and returns the formatted LogPayload.
// All formatting details like redaction are handled internally.
func (lf *LogFormatter) ProcessLogEntry(log map[string]any) LogPayload {
	// Apply redaction
	applyRedaction(log, lf.Exclude)

	// Format and return the log
	return LogPayload{
		OCISource: getFieldValue(log, "source", false).(string),
		Timestamp: getFieldValue(log, "time", false).(string),
		Data:      getFieldValue(log, "data", true).(map[string]any),
		DDSource:  getSource(log),
		Service:   lf.Service,
		Type:      getFieldValue(log, "type", false).(string),
		Oracle:    getFieldValue(log, "oracle", true).(map[string]any),
		DDTags:    lf.Tags,
	}
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

func getFieldValue(log map[string]any, field string, isMap bool) any {
	if isMap {
		if val, ok := log[field].(map[string]any); ok {
			return val
		}
		return make(map[string]any)
	}

	if val, ok := log[field].(string); ok {
		return val
	}
	return ""
}

func getSource(log map[string]any) string {
	oracle := getFieldValue(log, "oracle", true).(map[string]any)
	if loggroupID, exists := oracle["loggroupid"].(string); exists && loggroupID == AUDIT_LOGGROUP_ID {
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
