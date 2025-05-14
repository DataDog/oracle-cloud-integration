#!/bin/bash

# Read input JSON from stdin
# Through CLI run like this: 
# echo '{"region":"<oci-region-name>","regionKey":"<oci-region-key eg:IAD>"}' | ./docker_image_check.sh
input=$(cat)

REGION=$(echo "$input" | jq -r '.region')

# Region key in lower case otherwise it won't work
REGION_KEY=$(echo "$input" | jq -r '.regionKey' | tr '[:upper:]' '[:lower:]')

# Get the repository token
TOKEN=$(curl -s "https://$REGION_KEY.ocir.io/20180419/docker/token?service=$REGION_KEY.ocir.io&scope=repository:iddfxd5j9l2o/oci-datadog-forwarder/logs:pull" | jq -r .token)
URL="https://$REGION_KEY.ocir.io/v2/iddfxd5j9l2o/oci-datadog-forwarder/logs/manifests/latest"
# echo $URL $TOKEN_URL
# echo $TOKEN
HTTP_STATUS=$(curl -i -H "Authorization: Bearer $TOKEN" \
-H "Accept: application/vnd.oci.image.index.v1+json" -s -o /dev/null -w "%{http_code}" $URL)

if [[ "$HTTP_STATUS" =~ ^2 ]]; then
  echo "{\"value\": \"$REGION\", \"failure\": \"\"}"
else
  echo "{\"value\": \"$REGION\", \"failure\": \"failed-to-get\"}"
fi
