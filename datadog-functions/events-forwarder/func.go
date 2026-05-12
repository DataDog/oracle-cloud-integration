package main

import (
	"datadog-functions/events-forwarder/internal/handler"

	fdk "github.com/fnproject/fdk-go"
)

func main() {
	fdk.Handle(fdk.HandlerFunc(handler.MyHandler))
}
