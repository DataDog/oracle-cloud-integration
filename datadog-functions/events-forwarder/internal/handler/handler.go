package handler

import (
	"context"
	"fmt"
	"io"
	"log"

	"datadog-functions/events-forwarder/internal/formatter"
	"datadog-functions/lib/client"
)

var datadogClientFunc = client.NewDatadogClientWithTenancyAndSite

func MyHandler(ctx context.Context, in io.Reader, out io.Writer) {
	events, err := formatter.Decode(in)
	if err != nil {
		log.Printf("Error decoding event batch: %v", err)
		writeResponse(out, "error", "", err)
		return
	}

	ddclient, tenancyOCID, site, err := datadogClientFunc()
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
	ociHeaders := map[string]string{"Dd-Oci-Tenancy-Id": tenancyOCID}
	for _, payload := range payloads {
		if err := ddclient.SendMessageToDatadog(ctx, payload, url, ociHeaders); err != nil {
			log.Printf("Error sending events batch to Datadog: %v", err)
			writeResponse(out, "error", "", err)
			return
		}
	}

	writeResponse(out, "success", "Events sent to Datadog", nil)
}
