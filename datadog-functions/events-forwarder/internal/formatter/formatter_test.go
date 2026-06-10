package formatter

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"strings"
	"testing"
)

const sampleEvent = `{"eventType":"com.oraclecloud.objectstorage.deletebucket","eventID":"abc","data":{"resourceId":"ocid1.bucket.oc1..xyz"}}`

func TestDecode_InvalidJSON(t *testing.T) {
	if _, err := Decode(bytes.NewBufferString("not json")); err == nil {
		t.Fatal("expected error for invalid JSON, got nil")
	}
}

func TestDecode_NotObjectOrArray(t *testing.T) {
	if _, err := Decode(bytes.NewBufferString("123")); err == nil {
		t.Fatal("expected error for non-object/array JSON, got nil")
	}
}

// schMessage wraps an OCI Cloud Event as Service Connector Hub delivers it
// when the source is OCI Streaming.
func schMessage(event string) string {
	encoded := base64.StdEncoding.EncodeToString([]byte(event))
	return `{"streamPool":"ocid1.streampool.oc1..test","stream":"ocid1.stream.oc1..test","partition":"0","key":"","value":"` + encoded + `","offset":"0","timestamp":"2024-01-15T10:00:00.000Z"}`
}

func TestDecode_SCHStreamingArray(t *testing.T) {
	msg1 := schMessage(sampleEvent)
	msg2 := schMessage(sampleEvent)
	in := bytes.NewBufferString("[" + msg1 + "," + msg2 + "]")

	events, err := Decode(in)
	if err != nil {
		t.Fatalf("Decode: %v", err)
	}
	if len(events) != 2 {
		t.Fatalf("got %d events, want 2", len(events))
	}
	// Each decoded event should be the original OCI Cloud Event JSON.
	var decoded map[string]any
	if err := json.Unmarshal(events[0], &decoded); err != nil {
		t.Fatalf("unmarshal decoded event: %v", err)
	}
	if decoded["eventType"] != "com.oraclecloud.objectstorage.deletebucket" {
		t.Fatalf("eventType = %q, want %q", decoded["eventType"], "com.oraclecloud.objectstorage.deletebucket")
	}
}

func TestDecode_SCHStreamingSingleMessage(t *testing.T) {
	msg := schMessage(sampleEvent)
	in := bytes.NewBufferString("[" + msg + "]")

	events, err := Decode(in)
	if err != nil {
		t.Fatalf("Decode: %v", err)
	}
	if len(events) != 1 {
		t.Fatalf("got %d events, want 1", len(events))
	}
}

func TestDecode_SCHStreamingInvalidBase64(t *testing.T) {
	bad := `[{"streamPool":"x","value":"!!!notbase64!!!"}]`
	if _, err := Decode(bytes.NewBufferString(bad)); err == nil {
		t.Fatal("expected error for invalid base64, got nil")
	}
}

func TestDecode_SCHStreamingEmptyValue(t *testing.T) {
	empty := `[{"streamPool":"x","value":""}]`
	if _, err := Decode(bytes.NewBufferString(empty)); err == nil {
		t.Fatal("expected error for empty decoded value, got nil")
	}
}

func TestDecode_SCHStreamingNonJSONValue(t *testing.T) {
	encoded := base64.StdEncoding.EncodeToString([]byte("not json at all"))
	msg := `[{"streamPool":"x","value":"` + encoded + `"}]`
	if _, err := Decode(bytes.NewBufferString(msg)); err == nil {
		t.Fatal("expected error for non-JSON decoded value, got nil")
	}
}

func TestChunk_FitsInOnePayload(t *testing.T) {
	events := []json.RawMessage{json.RawMessage(sampleEvent), json.RawMessage(sampleEvent)}
	payloads, dropped := Chunk(events)
	if dropped != 0 {
		t.Fatalf("dropped = %d, want 0", dropped)
	}
	if len(payloads) != 1 {
		t.Fatalf("got %d payloads, want 1", len(payloads))
	}
	var decoded []map[string]any
	if err := json.Unmarshal(payloads[0], &decoded); err != nil {
		t.Fatalf("unmarshal payload: %v", err)
	}
	if len(decoded) != 2 {
		t.Fatalf("payload contains %d events, want 2", len(decoded))
	}
}

func TestChunk_Empty(t *testing.T) {
	payloads, dropped := Chunk(nil)
	if dropped != 0 {
		t.Fatalf("dropped = %d, want 0", dropped)
	}
	if payloads != nil {
		t.Fatalf("got %v payloads, want nil", payloads)
	}
}

func TestChunk_SplitsOnByteLimit(t *testing.T) {
	big := strings.Repeat("a", MaxBodyBytes/2-100)
	ev := json.RawMessage(`{"eventID":"` + big + `"}`)
	events := []json.RawMessage{ev, ev, ev}

	payloads, dropped := Chunk(events)
	if dropped != 0 {
		t.Fatalf("dropped = %d, want 0", dropped)
	}
	if len(payloads) != 2 {
		t.Fatalf("got %d payloads, want 2", len(payloads))
	}
	for i, p := range payloads {
		if len(p) > MaxBodyBytes {
			t.Fatalf("payload %d has size %d, exceeds MaxBodyBytes %d", i, len(p), MaxBodyBytes)
		}
	}
}

func TestChunk_DropsOversizeEvent(t *testing.T) {
	huge := strings.Repeat("a", MaxBodyBytes)
	oversize := json.RawMessage(`{"eventID":"` + huge + `"}`)
	normal := json.RawMessage(sampleEvent)

	payloads, dropped := Chunk([]json.RawMessage{normal, oversize, normal})
	if dropped != 1 {
		t.Fatalf("dropped = %d, want 1", dropped)
	}
	if len(payloads) != 1 {
		t.Fatalf("got %d payloads, want 1", len(payloads))
	}
	var decoded []map[string]any
	if err := json.Unmarshal(payloads[0], &decoded); err != nil {
		t.Fatalf("unmarshal payload: %v", err)
	}
	if len(decoded) != 2 {
		t.Fatalf("payload contains %d events, want 2", len(decoded))
	}
}

func TestChunk_SplitsOnCountLimit(t *testing.T) {
	count := MaxBatchCount + 5
	events := make([]json.RawMessage, count)
	for i := range events {
		events[i] = json.RawMessage(`{}`)
	}

	payloads, dropped := Chunk(events)
	if dropped != 0 {
		t.Fatalf("dropped = %d, want 0", dropped)
	}
	if len(payloads) != 2 {
		t.Fatalf("got %d payloads, want 2", len(payloads))
	}

	var first []map[string]any
	if err := json.Unmarshal(payloads[0], &first); err != nil {
		t.Fatalf("unmarshal first payload: %v", err)
	}
	if len(first) != MaxBatchCount {
		t.Fatalf("first payload has %d events, want %d", len(first), MaxBatchCount)
	}

	var second []map[string]any
	if err := json.Unmarshal(payloads[1], &second); err != nil {
		t.Fatalf("unmarshal second payload: %v", err)
	}
	if len(second) != 5 {
		t.Fatalf("second payload has %d events, want 5", len(second))
	}
}
