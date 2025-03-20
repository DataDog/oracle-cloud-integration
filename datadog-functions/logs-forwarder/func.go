package main

import (
	"datadog-functions/logs-forwarder/internal/handler"

	fdk "github.com/fnproject/fdk-go"
)

func main() {
	fdk.Handle(fdk.HandlerFunc(handler.MyHandler))
}
