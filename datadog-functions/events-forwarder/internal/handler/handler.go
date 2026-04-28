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

	payloads, dropped := formatter.Chunk(events)
	if dropped > 0 {
		log.Printf("Dropped %d event(s) exceeding the %d byte intake limit", dropped, formatter.MaxBodyBytes)
	}

	url := fmt.Sprintf("https://cloudplatform-intake.%s/api/v2/cloudchanges", site)
	for _, payload := range payloads {
		if err := ddclient.SendMessageToDatadog(ctx, payload, url); err != nil {
			log.Printf("Error sending events batch to Datadog: %v", err)
			writeResponse(out, "error", "", err)
			return
		}
	}

	writeResponse(out, "success", "Events sent to Datadog", nil)
}
