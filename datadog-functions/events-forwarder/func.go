package main

import (
	"datadog-functions/events-forwarder/internal/handler"

	fdk "github.com/fnproject/fdk-go"
)

// Version is stamped at build time via -ldflags "-X main.Version=<tag>" so
// hubmanager's version-check invocation (see handler.Version) can read back
// what's actually baked into this image, not what OCI's function record
// claims should be running.
var Version = "unknown"

func main() {
	handler.Version = Version
	fdk.Handle(fdk.HandlerFunc(handler.MyHandler))
}
