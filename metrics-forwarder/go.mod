module oracle-cloud-integration/metrics-forwarder

go 1.23.4

require (
	github.com/DataDog/datadog-api-client-go/v2 v2.36.1
	github.com/fnproject/fdk-go v0.0.53
	github.com/stretchr/testify v1.10.0
	oracle-cloud-integration/internal v0.0.0
)

replace oracle-cloud-integration/internal => ../internal

require (
	github.com/DataDog/zstd v1.5.2 // indirect
	github.com/davecgh/go-spew v1.1.1 // indirect
	github.com/goccy/go-json v0.10.2 // indirect
	github.com/gofrs/flock v0.8.1 // indirect
	github.com/golang/protobuf v1.5.3 // indirect
	github.com/oracle/oci-go-sdk/v65 v65.87.0 // indirect
	github.com/pmezard/go-difflib v1.0.0 // indirect
	github.com/sony/gobreaker v0.5.0 // indirect
	github.com/stretchr/objx v0.5.2 // indirect
	golang.org/x/net v0.17.0 // indirect
	golang.org/x/oauth2 v0.10.0 // indirect
	golang.org/x/sys v0.13.0 // indirect
	google.golang.org/appengine v1.6.7 // indirect
	google.golang.org/protobuf v1.31.0 // indirect
	gopkg.in/yaml.v3 v3.0.1 // indirect
)
