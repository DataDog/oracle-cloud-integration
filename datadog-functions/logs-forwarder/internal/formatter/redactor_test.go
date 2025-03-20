package formatter

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestRedactField(t *testing.T) {
	tests := []struct {
		name      string
		log       map[string]interface{}
		fieldPath string
		expected  map[string]interface{}
	}{
		{
			name: "Redact top-level field",
			log: map[string]interface{}{
				"password": "secret",
				"user":     "admin",
			},
			fieldPath: "password",
			expected: map[string]interface{}{
				"password": "******",
				"user":     "admin",
			},
		},
		{
			name: "Redact nested field",
			log: map[string]interface{}{
				"user": map[string]interface{}{
					"password": "secret",
					"name":     "admin",
				},
			},
			fieldPath: "user.password",
			expected: map[string]interface{}{
				"user": map[string]interface{}{
					"password": "******",
					"name":     "admin",
				},
			},
		},
		{
			name: "Field path does not exist",
			log: map[string]interface{}{
				"user": map[string]interface{}{
					"name": "admin",
				},
			},
			fieldPath: "user.password",
			expected: map[string]interface{}{
				"user": map[string]interface{}{
					"name": "admin",
				},
			},
		},
		{
			name: "Intermediate path is not a map",
			log: map[string]interface{}{
				"user": "admin",
			},
			fieldPath: "user.password",
			expected: map[string]interface{}{
				"user": "admin",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			redactField(tt.log, tt.fieldPath)
			assert.Equal(t, tt.expected, tt.log)
		})
	}
}
