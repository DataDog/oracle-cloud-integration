// Package handler implements the events-forwarder OCI Function entry point.
//
// The function receives a batch of OCI cloud events from a Service Connector
// Hub and forwards them to Datadog's cloudchanges intake. It is a thin
// pass-through — all event filtering and schema mapping happens server-side
// in cloudchange-worker.
package handler

import (
	"context"
	"fmt"
	"io"
	"log"

	"datadog-functions/events-forwarder/internal/formatter"
	"datadog-functions/lib/client"
)

var datadogClientFunc = client.NewDatadogClientWithSite

// MyHandler is the OCI Function entry point invoked by the Service Connector
// Hub for each batch of events.
func MyHandler(ctx context.Context, in io.Reader, out io.Writer) {
	events, err := formatter.Decode(in)
	if err != nil {
		log.Printf("Error decoding event batch: %v", err)
		writeResponse(out, "error", "", err)
		return
	}

	ddclient, site, err := datadogClientFunc()
	if err != nil {
		log.Println(err)
		writeResponse(out, "error", "", err)
		return
	}

	payloads, chunkErr := formatter.Chunk(events)
	if chunkErr != nil {
		// Oversize events are dropped; remaining payloads still ship.
		log.Printf("Warning: %v", chunkErr)
	}

	url := fmt.Sprintf("https://cloudplatform-intake.%s/api/v2/cloudchanges", site)
	for i, payload := range payloads {
		fmt.Printf("Events batch %d/%d uncompressed=%.2fKB\n", i+1, len(payloads), float64(len(payload))/1024.0)
		if err := ddclient.SendMessageToDatadog(ctx, payload, url); err != nil {
			log.Printf("Error sending events batch to Datadog: %v", err)
			writeResponse(out, "error", "", err)
			return
		}
	}

	writeResponse(out, "success", "Events sent to Datadog", nil)
}
