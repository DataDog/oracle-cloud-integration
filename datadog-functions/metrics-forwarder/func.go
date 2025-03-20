package main

import (
	"datadog-functions/metrics-forwarder/internal/handler"

	fdk "github.com/fnproject/fdk-go"
)

func main() {
	fdk.Handle(fdk.HandlerFunc(handler.MyHandler))
}
