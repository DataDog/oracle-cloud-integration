package client

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"time"
)

// coldStartMetric identifies which image tag is actually running in a given
// region, independent of what OCI's function record reports — the two can
// diverge under registry/image-cache propagation lag after hubmanager applies
// an update.
const coldStartMetric = "datadog.oci.forwarder.cold_start"

// EmitColdStart reports a forwarder's actual running version once per
// container cold start. It must be called from main(), never from the
// per-invocation handler: the version is fixed for a container's lifetime, so
// per-invocation emission would only add volume without adding signal.
//
// This is best-effort: any failure here is logged and swallowed so it can
// never block the function from serving traffic.
func EmitColdStart(forwarder, version string) {
	ddclient, site, err := NewDatadogClientWithSite()
	if err != nil {
		log.Printf("cold start metric skipped: %v", err)
		return
	}

	payload, err := json.Marshal(map[string]any{
		"series": []map[string]any{{
			"metric": coldStartMetric,
			"type":   3, // gauge; avoids count's interval-normalization for a point-in-time signal
			"points": []map[string]any{{"timestamp": time.Now().Unix(), "value": 1}},
			"tags": []string{
				"forwarder:" + forwarder,
				"version:" + version,
				"region:" + os.Getenv("HOME_REGION"),
			},
		}},
	})
	if err != nil {
		log.Printf("cold start metric skipped: %v", err)
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	url := fmt.Sprintf("https://api.%s/api/v2/series", site)
	if err := ddclient.SendMessageToDatadog(ctx, payload, url); err != nil {
		log.Printf("cold start metric send failed: %v", err)
		return
	}
	log.Printf("cold start: forwarder=%s version=%s", forwarder, version)
}
