module datadog-functions/metrics-forwarder

go 1.24.1

require (
	datadog-functions/internal v0.0.0
	github.com/fnproject/fdk-go v0.0.55
	github.com/stretchr/testify v1.10.0
)

replace datadog-functions/internal => ../internal

require (
	github.com/DataDog/datadog-api-client-go/v2 v2.36.1 // indirect
	github.com/DataDog/zstd v1.5.6 // indirect
	github.com/davecgh/go-spew v1.1.1 // indirect
	github.com/goccy/go-json v0.10.5 // indirect
	github.com/gofrs/flock v0.12.1 // indirect
	github.com/oracle/oci-go-sdk/v65 v65.87.0 // indirect
	github.com/pmezard/go-difflib v1.0.0 // indirect
	github.com/sony/gobreaker v1.0.0 // indirect
	github.com/stretchr/objx v0.5.2 // indirect
	golang.org/x/oauth2 v0.28.0 // indirect
	golang.org/x/sys v0.31.0 // indirect
	gopkg.in/yaml.v3 v3.0.1 // indirect
)
