// Package formatter decodes and chunks an OCI cloud-events batch into
// payloads sized for the cloudchanges intake. Events are forwarded
// unchanged — schema mapping happens server-side in cloudchange-worker.
package formatter

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
)

// streamingMessage is the per-message envelope that Service Connector Hub
// delivers to Functions when the source is OCI Streaming. The actual OCI
// Cloud Event JSON is base64-encoded in the Value field.
type streamingMessage struct {
	Value string `json:"value"`
}

// isStreamingFormat reports whether msgs looks like an SCH streaming batch:
// each element has a "value" field but no "eventType" field (which is
// mandatory in every OCI Cloud Event envelope).
func isStreamingFormat(msgs []json.RawMessage) bool {
	if len(msgs) == 0 {
		return false
	}
	var first map[string]json.RawMessage
	if err := json.Unmarshal(msgs[0], &first); err != nil {
		return false
	}
	_, hasValue := first["value"]
	_, hasEventType := first["eventType"]
	return hasValue && !hasEventType
}

// decodeStreamingMessages base64-decodes the "value" field of each SCH
// streaming message and returns the inner OCI Cloud Event JSON payloads.
func decodeStreamingMessages(msgs []json.RawMessage) ([]json.RawMessage, error) {
	out := make([]json.RawMessage, 0, len(msgs))
	for i, msg := range msgs {
		var sm streamingMessage
		if err := json.Unmarshal(msg, &sm); err != nil {
			return nil, fmt.Errorf("streaming message %d: failed to unmarshal: %w", i, err)
		}
		decoded, err := base64.StdEncoding.DecodeString(sm.Value)
		if err != nil {
			return nil, fmt.Errorf("streaming message %d: failed to base64-decode value: %w", i, err)
		}
		out = append(out, json.RawMessage(decoded))
	}
	return out, nil
}

// Intake limits enforced by cloudplatform-intake/api/v2/cloudchanges.
const (
	MaxBodyBytes  = 5 * 1024 * 1024
	MaxBatchCount = 65536
)

// Decode accepts:
//  1. A single OCI CloudEvents envelope
//  2. An array of OCI CloudEvents envelopes
//  3. An array of OCI Streaming messages (SCH format) — each envelope's
//     "value" field is base64-decoded to extract the inner OCI Cloud Event.
//
// Events are returned as RawMessage so downstream chunking can operate on
// encoded sizes without re-encoding each element.
func Decode(in io.Reader) ([]json.RawMessage, error) {
	var body json.RawMessage
	if err := json.NewDecoder(in).Decode(&body); err != nil {
		return nil, fmt.Errorf("failed to decode JSON: %w", err)
	}

	var arr []json.RawMessage
	if err := json.Unmarshal(body, &arr); err == nil {
		if isStreamingFormat(arr) {
			return decodeStreamingMessages(arr)
		}
		return arr, nil
	}

	var obj map[string]any
	if err := json.Unmarshal(body, &obj); err != nil {
		return nil, fmt.Errorf("invalid JSON format: expected object or array of objects: %w", err)
	}
	return []json.RawMessage{body}, nil
}

// Chunk splits events into JSON-array payloads that respect the intake's
// per-request size and count limits. Events larger than MaxBodyBytes
// individually cannot fit in any payload and are dropped; the count of
// dropped events is returned alongside the payloads so the caller can log
// it.
func Chunk(events []json.RawMessage) (payloads [][]byte, dropped int) {
	if len(events) == 0 {
		return nil, 0
	}

	var (
		current     []json.RawMessage
		currentSize = 2 // "[" + "]"
	)

	flush := func() {
		if len(current) == 0 {
			return
		}
		buf, _ := json.Marshal(current)
		payloads = append(payloads, buf)
		current = current[:0]
		currentSize = 2
	}

	for _, ev := range events {
		evSize := len(ev)
		if evSize+2 > MaxBodyBytes {
			// OCI events average ~1KB; a single event reaching 5MB is not expected in practice.
			dropped++
			continue
		}

		addSize := evSize
		if len(current) > 0 {
			addSize++ // comma separator
		}

		if currentSize+addSize > MaxBodyBytes || len(current)+1 > MaxBatchCount {
			flush()
			addSize = evSize
		}

		current = append(current, ev)
		currentSize += addSize
	}
	flush()

	return payloads, dropped
}
