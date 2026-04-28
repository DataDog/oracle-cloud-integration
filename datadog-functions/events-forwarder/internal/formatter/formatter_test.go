package formatter

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
)

const sampleEvent = `{"eventType":"com.oraclecloud.objectstorage.deletebucket","eventID":"abc","data":{"resourceId":"ocid1.bucket.oc1..xyz"}}`

func TestDecode_Array(t *testing.T) {
	in := bytes.NewBufferString("[" + sampleEvent + "," + sampleEvent + "]")
	events, err := Decode(in)
	assert.NoError(t, err)
	assert.Len(t, events, 2)
}

func TestDecode_SingleObject(t *testing.T) {
	in := bytes.NewBufferString(sampleEvent)
	events, err := Decode(in)
	assert.NoError(t, err)
	assert.Len(t, events, 1)
}

func TestDecode_InvalidJSON(t *testing.T) {
	in := bytes.NewBufferString("not json")
	_, err := Decode(in)
	assert.Error(t, err)
}

func TestDecode_NotObjectOrArray(t *testing.T) {
	in := bytes.NewBufferString("123")
	_, err := Decode(in)
	assert.Error(t, err)
}

func TestChunk_FitsInOnePayload(t *testing.T) {
	events := []json.RawMessage{
		json.RawMessage(sampleEvent),
		json.RawMessage(sampleEvent),
	}
	payloads, err := Chunk(events)
	assert.NoError(t, err)
	assert.Len(t, payloads, 1)

	var decoded []map[string]any
	assert.NoError(t, json.Unmarshal(payloads[0], &decoded))
	assert.Len(t, decoded, 2)
}

func TestChunk_Empty(t *testing.T) {
	payloads, err := Chunk(nil)
	assert.NoError(t, err)
	assert.Nil(t, payloads)
}

func TestChunk_SplitsOnByteLimit(t *testing.T) {
	// Build events that each occupy roughly half of MaxBodyBytes so two events
	// must split across payloads.
	big := strings.Repeat("a", MaxBodyBytes/2-100)
	ev := json.RawMessage(`{"eventID":"` + big + `"}`)
	events := []json.RawMessage{ev, ev, ev}

	payloads, err := Chunk(events)
	assert.NoError(t, err)
	assert.GreaterOrEqual(t, len(payloads), 2)

	for _, p := range payloads {
		assert.LessOrEqual(t, len(p), MaxBodyBytes)
	}
}

func TestChunk_DropsOversizeEvent(t *testing.T) {
	huge := strings.Repeat("a", MaxBodyBytes)
	oversize := json.RawMessage(`{"eventID":"` + huge + `"}`)
	normal := json.RawMessage(sampleEvent)

	payloads, err := Chunk([]json.RawMessage{normal, oversize, normal})
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "exceeded")
	// Normal events still ship.
	assert.Len(t, payloads, 1)
	var decoded []map[string]any
	assert.NoError(t, json.Unmarshal(payloads[0], &decoded))
	assert.Len(t, decoded, 2)
}

func TestChunk_SplitsOnCountLimit(t *testing.T) {
	// Synthesize events just past MaxBatchCount to verify a count-based split.
	count := MaxBatchCount + 5
	events := make([]json.RawMessage, count)
	for i := range events {
		events[i] = json.RawMessage(`{}`)
	}

	payloads, err := Chunk(events)
	assert.NoError(t, err)
	assert.Len(t, payloads, 2)

	var first []map[string]any
	assert.NoError(t, json.Unmarshal(payloads[0], &first))
	assert.Equal(t, MaxBatchCount, len(first))

	var second []map[string]any
	assert.NoError(t, json.Unmarshal(payloads[1], &second))
	assert.Equal(t, 5, len(second))
}
