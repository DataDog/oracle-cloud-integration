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

// Intake limits enforced by cloudplatform-intake/api/v2/cloudchanges.
const (
	MaxBodyBytes  = 5 * 1024 * 1024
	MaxBatchCount = 65536
)

// Decode accepts an array of OCI Streaming messages as delivered by Service
// Connector Hub. Each message's "value" field is base64-decoded to extract
// the inner OCI Cloud Event JSON. Events are returned as RawMessage so
// downstream chunking can operate on encoded sizes without re-encoding.
func Decode(in io.Reader) ([]json.RawMessage, error) {
	var msgs []streamingMessage
	if err := json.NewDecoder(in).Decode(&msgs); err != nil {
		return nil, fmt.Errorf("failed to decode JSON: %w", err)
	}
	out := make([]json.RawMessage, 0, len(msgs))
	for i, sm := range msgs {
		// OCI Streaming encodes message values as standard RFC 4648 base64 (with padding).
		decoded, err := base64.StdEncoding.DecodeString(sm.Value)
		if err != nil {
			return nil, fmt.Errorf("streaming message %d: failed to base64-decode value: %w", i, err)
		}
		if len(decoded) == 0 {
			return nil, fmt.Errorf("streaming message %d: decoded value is empty", i)
		}
		if decoded[0] != '{' {
			return nil, fmt.Errorf("streaming message %d: decoded value is not a JSON object", i)
		}
		if !json.Valid(decoded) {
			return nil, fmt.Errorf("streaming message %d: decoded value is not valid JSON", i)
		}
		out = append(out, json.RawMessage(decoded))
	}
	return out, nil
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
