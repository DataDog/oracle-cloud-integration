package formatter

import (
	"encoding/json"
	"os"
)

var excludeSet = map[string]struct{}{
	"data.identity.credentials":                           {},
	"data.request.headers.Authorization":                  {},
	"data.request.headers.authorization":                  {},
	"data.request.headers.X-OCI-LB-PrivateAccessMetadata": {},
	"data.request.headers.opc-principal":                  {},
}

// Loads the exclude list from an environment variable
// EXCLUDE Env Variable Example: '{ "data.identity": [ "credentials"], "data.request.headers": [ "authorization", "Authorization", "X-OCI-LB-PrivateAccessMetadata", "opc-principal" ] }'
func getExcludeList() (map[string]struct{}, error) {
	excludeJSON := os.Getenv("EXCLUDE")
	if excludeJSON == "" {
		return excludeSet, nil
	}

	var excludeMap map[string][]string
	err := json.Unmarshal([]byte(excludeJSON), &excludeMap)
	if err != nil {
		return nil, err
	}

	for parentKey, childKeys := range excludeMap {
		for _, childKey := range childKeys {
			excludeSet[parentKey+"."+childKey] = struct{}{}
		}
	}
	return excludeSet, nil
}
