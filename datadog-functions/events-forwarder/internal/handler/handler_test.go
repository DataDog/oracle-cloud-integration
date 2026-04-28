package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"os"
	"testing"

	"datadog-functions/lib/client"

	fdk "github.com/fnproject/fdk-go"
	"github.com/stretchr/testify/assert"
)

func getContext() context.Context {
	return fdk.WithContext(context.Background(), mockFnContext{})
}

type mockFnContext struct{}

func (mockFnContext) AppID() string                          { return "mock-app-id" }
func (mockFnContext) AppName() string                        { return "mock-app-name" }
func (mockFnContext) FnID() string                           { return "mock-fn-id" }
func (mockFnContext) FnName() string                         { return "mock-fn-name" }
func (mockFnContext) CallID() string                         { return "mock-call-id" }
func (mockFnContext) Config() map[string]string              { return nil }
func (mockFnContext) Header() http.Header                    { return nil }
func (mockFnContext) ContentType() string                    { return "" }
func (mockFnContext) TracingContextData() fdk.TracingContext { return nil }

const eventEnvelope = `{"eventType":"com.oraclecloud.objectstorage.deletebucket","eventID":"abc","data":{"resourceId":"ocid1.bucket.oc1..xyz"}}`

func withTestClient(t *testing.T) {
	t.Helper()
	original := datadogClientFunc
	t.Cleanup(func() { datadogClientFunc = original })
	datadogClientFunc = client.NewTestDatadogClientWithSite
}

func TestMyHandler_ArrayPayload(t *testing.T) {
	withTestClient(t)

	in := bytes.NewBufferString("[" + eventEnvelope + "," + eventEnvelope + "]")
	out := &bytes.Buffer{}
	MyHandler(getContext(), in, out)

	var resp fnResponse
	assert.NoError(t, json.Unmarshal(out.Bytes(), &resp))
	assert.Equal(t, "success", resp.Status)
	assert.Equal(t, "Events sent to Datadog", resp.Message)
}

func TestMyHandler_SingleEnvelope(t *testing.T) {
	withTestClient(t)

	in := bytes.NewBufferString(eventEnvelope)
	out := &bytes.Buffer{}
	MyHandler(getContext(), in, out)

	var resp fnResponse
	assert.NoError(t, json.Unmarshal(out.Bytes(), &resp))
	assert.Equal(t, "success", resp.Status)
}

func TestMyHandler_InvalidJSON(t *testing.T) {
	withTestClient(t)

	in := bytes.NewBufferString("not json")
	out := &bytes.Buffer{}
	MyHandler(getContext(), in, out)

	var resp fnResponse
	assert.NoError(t, json.Unmarshal(out.Bytes(), &resp))
	assert.Equal(t, "error", resp.Status)
	assert.Contains(t, resp.Error, "decode JSON")
}

func TestMyHandler_MissingEnv(t *testing.T) {
	// Skip withTestClient so the real client constructor runs and the env-var check fires.
	original := datadogClientFunc
	t.Cleanup(func() { datadogClientFunc = original })
	datadogClientFunc = client.NewDatadogClientWithSite

	os.Unsetenv("DD_SITE")

	in := bytes.NewBufferString(eventEnvelope)
	out := &bytes.Buffer{}
	MyHandler(getContext(), in, out)

	var resp fnResponse
	assert.NoError(t, json.Unmarshal(out.Bytes(), &resp))
	assert.Equal(t, "error", resp.Status)
	assert.Contains(t, resp.Error, "DD_SITE")
}
