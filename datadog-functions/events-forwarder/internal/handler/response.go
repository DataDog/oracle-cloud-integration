package handler

import (
	"encoding/json"
	"io"
	"log"

	fdk "github.com/fnproject/fdk-go"
)

type fnResponse struct {
	Status  string `json:"status,omitempty"`
	Message string `json:"message,omitempty"`
	Error   string `json:"error,omitempty"`
	Version string `json:"version,omitempty"`
}

func writeResponse(out io.Writer, status string, message string, err error) {
	fdk.AddHeader(out, "Content-Type", "application/json")
	resp := fnResponse{
		Status:  status,
		Message: message,
	}

	if err != nil {
		resp.Error = err.Error()
	}

	jsonResp, jsonErr := json.Marshal(resp)
	if jsonErr != nil {
		log.Printf("Error marshalling response: %v", jsonErr)
		fdk.WriteStatus(out, 500)
		out.Write([]byte(`{"status":"error","error":"Internal server error"}`))
		return
	}

	if status == "success" {
		fdk.WriteStatus(out, 200)
	} else {
		fdk.WriteStatus(out, 500)
	}
	out.Write(jsonResp)
}

// writeVersionResponse answers a hubmanager version-check invocation with this
// forwarder's build-stamped version, bypassing writeResponse's status/message
// shape since this is a data query, not a forward-path outcome.
func writeVersionResponse(out io.Writer, version string) {
	fdk.AddHeader(out, "Content-Type", "application/json")
	jsonResp, err := json.Marshal(fnResponse{Status: "success", Version: version})
	if err != nil {
		log.Printf("Error marshalling version response: %v", err)
		fdk.WriteStatus(out, 500)
		out.Write([]byte(`{"status":"error","error":"Internal server error"}`))
		return
	}
	fdk.WriteStatus(out, 200)
	out.Write(jsonResp)
}
