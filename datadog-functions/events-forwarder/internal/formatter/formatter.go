// Package formatter decodes and chunks the OCI cloud-events batch delivered by
// the Service Connector Hub into payloads sized for the cloudchanges intake.
//
// Input from OCH is a JSON array of OCI CloudEvents envelopes (or a single
// envelope). The events are forwarded unchanged — mapping to the unified
// cloudchange schema happens server-side in cloudchange-worker.
package formatter

import (
	"encoding/json"
	"fmt"
	"io"
)

// Intake limits enforced by cloudplatform-intake/api/v2/cloudchanges.
const (
	MaxBodyBytes  = 5 * 1024 * 1024 // 5 MB uncompressed
	MaxBatchCount = 65536
)

// Decode reads a JSON payload that is either a single OCI CloudEvents
// envelope or an array of envelopes, and returns them as RawMessage so that
// downstream chunking can operate on encoded sizes without re-encoding.
func Decode(in io.Reader) ([]json.RawMessage, error) {
	var body json.RawMessage
	if err := json.NewDecoder(in).Decode(&body); err != nil {
		return nil, fmt.Errorf("failed to decode JSON: %w", err)
	}

	var arr []json.RawMessage
	if err := json.Unmarshal(body, &arr); err == nil {
		return arr, nil
	}

	// Fall back to a single object.
	var obj map[string]any
	if err := json.Unmarshal(body, &obj); err != nil {
		return nil, fmt.Errorf("invalid JSON format: expected object or array of objects: %w", err)
	}
	return []json.RawMessage{body}, nil
}

// Chunk splits events into JSON-array payloads that respect the intake's
// per-request size and count limits. Each returned payload is a complete
// JSON array ready to be sent.
//
// A single event larger than MaxBodyBytes is dropped with an error returned
// for the caller to log; the remaining events still chunk normally.
func Chunk(events []json.RawMessage) ([][]byte, error) {
	if len(events) == 0 {
		return nil, nil
	}

	var (
		payloads [][]byte
		current  []json.RawMessage
		// Account for "[", "]" and the commas between elements.
		currentSize = 2
		oversize    int
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
			oversize++
			continue
		}

		// +1 for the comma separator if this isn't the first element.
		addSize := evSize
		if len(current) > 0 {
			addSize++
		}

		if currentSize+addSize > MaxBodyBytes || len(current)+1 > MaxBatchCount {
			flush()
			addSize = evSize
		}

		current = append(current, ev)
		currentSize += addSize
	}
	flush()

	if oversize > 0 {
		return payloads, fmt.Errorf("%d event(s) exceeded the %d byte intake limit and were dropped", oversize, MaxBodyBytes)
	}
	return payloads, nil
}
