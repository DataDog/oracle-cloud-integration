package handler

import (
	"encoding/json"
	"io"
	"log"

	fdk "github.com/fnproject/fdk-go"
)

// FnResponse defines the standard JSON response format
type fnResponse struct {
	Status  string `json:"status,omitempty"`
	Message string `json:"message,omitempty"`
	Error   string `json:"error,omitempty"`
}

// writeResponse writes a structured JSON response
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
