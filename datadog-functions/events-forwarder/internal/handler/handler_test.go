package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"os"
	"strings"
	"testing"

	"datadog-functions/lib/client"

	fdk "github.com/fnproject/fdk-go"
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

func runHandler(t *testing.T, body string) fnResponse {
	t.Helper()
	in := bytes.NewBufferString(body)
	out := &bytes.Buffer{}
	MyHandler(getContext(), in, out)

	var resp fnResponse
	if err := json.Unmarshal(out.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal response: %v (raw=%q)", err, out.String())
	}
	return resp
}

func TestMyHandler_ArrayPayload(t *testing.T) {
	withTestClient(t)

	resp := runHandler(t, "["+eventEnvelope+","+eventEnvelope+"]")
	if resp.Status != "success" {
		t.Fatalf("status = %q, want success (resp=%+v)", resp.Status, resp)
	}
	if resp.Message != "Events sent to Datadog" {
		t.Fatalf("message = %q, want %q", resp.Message, "Events sent to Datadog")
	}
}

func TestMyHandler_SingleEnvelope(t *testing.T) {
	withTestClient(t)

	resp := runHandler(t, eventEnvelope)
	if resp.Status != "success" {
		t.Fatalf("status = %q, want success (resp=%+v)", resp.Status, resp)
	}
}

func TestMyHandler_InvalidJSON(t *testing.T) {
	withTestClient(t)

	resp := runHandler(t, "not json")
	if resp.Status != "error" {
		t.Fatalf("status = %q, want error", resp.Status)
	}
	if !strings.Contains(resp.Error, "decode JSON") {
		t.Fatalf("error = %q, want substring %q", resp.Error, "decode JSON")
	}
}

func TestMyHandler_MissingEnv(t *testing.T) {
	// Skip withTestClient so the real client constructor runs and the env-var check fires.
	original := datadogClientFunc
	t.Cleanup(func() { datadogClientFunc = original })
	datadogClientFunc = client.NewDatadogClientWithSite

	os.Unsetenv("DD_SITE")

	resp := runHandler(t, eventEnvelope)
	if resp.Status != "error" {
		t.Fatalf("status = %q, want error", resp.Status)
	}
	if !strings.Contains(resp.Error, "DD_SITE") {
		t.Fatalf("error = %q, want substring %q", resp.Error, "DD_SITE")
	}
}
