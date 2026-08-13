package main

import (
	"datadog-functions/events-forwarder/internal/handler"
	"datadog-functions/lib/client"

	fdk "github.com/fnproject/fdk-go"
)

// Version is stamped at build time via -ldflags "-X main.Version=<tag>" so it
// reflects what's actually baked into this image, not what OCI's function
// record claims should be running.
var Version = "unknown"

func main() {
	client.EmitColdStart("events", Version)
	fdk.Handle(fdk.HandlerFunc(handler.MyHandler))
}
