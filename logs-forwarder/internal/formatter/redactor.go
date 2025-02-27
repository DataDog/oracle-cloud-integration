package formatter

import (
	"strings"
)

// Redacts sensitive fields in JSON data
func applyRedaction(log map[string]interface{}, excludeSet map[string]struct{}) {
	for fieldPath := range excludeSet {
		redactField(log, fieldPath)
	}
}

func redactField(log map[string]interface{}, fieldPath string) {
	keys := strings.Split(fieldPath, ".")
	current := log
	for i, key := range keys {
		if val, exists := current[key]; exists {
			// If it's the last key, redact it
			if i == len(keys)-1 {
				current[key] = "******"
			} else if nested, isMap := val.(map[string]interface{}); isMap {
				current = nested
			} else {
				return
			}
		}
	}
}
