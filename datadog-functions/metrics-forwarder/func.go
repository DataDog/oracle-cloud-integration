package main

import (
	"datadog-functions/lib/client"
	"datadog-functions/metrics-forwarder/internal/handler"

	fdk "github.com/fnproject/fdk-go"
)

// Version is stamped at build time via -ldflags "-X main.Version=<tag>" so it
// reflects what's actually baked into this image, not what OCI's function
// record claims should be running.
var Version = "unknown"

func main() {
	client.EmitColdStart("metrics", Version)
	fdk.Handle(fdk.HandlerFunc(handler.MyHandler))
}
