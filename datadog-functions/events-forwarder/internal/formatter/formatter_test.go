package formatter

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
)

const sampleEvent = `{"eventType":"com.oraclecloud.objectstorage.deletebucket","eventID":"abc","data":{"resourceId":"ocid1.bucket.oc1..xyz"}}`

func TestDecode_Array(t *testing.T) {
	in := bytes.NewBufferString("[" + sampleEvent + "," + sampleEvent + "]")
	events, err := Decode(in)
	if err != nil {
		t.Fatalf("Decode: %v", err)
	}
	if len(events) != 2 {
		t.Fatalf("got %d events, want 2", len(events))
	}
}

func TestDecode_SingleObject(t *testing.T) {
	in := bytes.NewBufferString(sampleEvent)
	events, err := Decode(in)
	if err != nil {
		t.Fatalf("Decode: %v", err)
	}
	if len(events) != 1 {
		t.Fatalf("got %d events, want 1", len(events))
	}
}

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

func TestStamp_AddsFields(t *testing.T) {
	events := []json.RawMessage{json.RawMessage(sampleEvent), json.RawMessage(sampleEvent)}
	stamped, err := Stamp(events, "ocid1.tenancy.oc1..test")
	if err != nil {
		t.Fatalf("Stamp: %v", err)
	}
	if len(stamped) != len(events) {
		t.Fatalf("got %d events, want %d", len(stamped), len(events))
	}
	for i, ev := range stamped {
		var m map[string]any
		if err := json.Unmarshal(ev, &m); err != nil {
			t.Fatalf("unmarshal event %d: %v", i, err)
		}
		if got, ok := m["ddForwarder"]; !ok || got != "oci" {
			t.Errorf("event %d: ddForwarder = %v, want \"oci\"", i, got)
		}
		if got, ok := m["tenancyOCID"]; !ok || got != "ocid1.tenancy.oc1..test" {
			t.Errorf("event %d: tenancyOCID = %v, want \"ocid1.tenancy.oc1..test\"", i, got)
		}
	}
}

func TestStamp_PreservesExistingFields(t *testing.T) {
	stamped, err := Stamp([]json.RawMessage{json.RawMessage(sampleEvent)}, "")
	if err != nil {
		t.Fatalf("Stamp: %v", err)
	}
	var m map[string]any
	if err := json.Unmarshal(stamped[0], &m); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if _, ok := m["eventType"]; !ok {
		t.Error("eventType field lost after Stamp")
	}
	if _, ok := m["data"]; !ok {
		t.Error("data field lost after Stamp")
	}
}

func TestStamp_Empty(t *testing.T) {
	stamped, err := Stamp(nil, "")
	if err != nil {
		t.Fatalf("Stamp(nil): %v", err)
	}
	if len(stamped) != 0 {
		t.Fatalf("got %d events, want 0", len(stamped))
	}
}

func TestStamp_InvalidJSON(t *testing.T) {
	if _, err := Stamp([]json.RawMessage{json.RawMessage("not json")}, ""); err == nil {
		t.Fatal("expected error for invalid JSON, got nil")
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
