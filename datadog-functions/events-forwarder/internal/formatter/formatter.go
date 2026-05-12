// Package formatter decodes and chunks an OCI cloud-events batch into
// payloads sized for the cloudchanges intake. Events are forwarded
// unchanged — schema mapping happens server-side in cloudchange-worker.
package formatter

import (
	"encoding/json"
	"fmt"
	"io"
)

// Intake limits enforced by cloudplatform-intake/api/v2/cloudchanges.
const (
	MaxBodyBytes  = 5 * 1024 * 1024
	MaxBatchCount = 65536
)

// Decode accepts either a single OCI CloudEvents envelope or an array of
// envelopes. Events are returned as RawMessage so downstream chunking can
// operate on encoded sizes without re-encoding each element.
func Decode(in io.Reader) ([]json.RawMessage, error) {
	var body json.RawMessage
	if err := json.NewDecoder(in).Decode(&body); err != nil {
		return nil, fmt.Errorf("failed to decode JSON: %w", err)
	}

	var arr []json.RawMessage
	if err := json.Unmarshal(body, &arr); err == nil {
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
