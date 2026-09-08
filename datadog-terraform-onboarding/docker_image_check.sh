#!/bin/bash

# Read input JSON from stdin
# Through CLI run like this: 
# echo '{"region":"<oci-region-name>","regionKey":"<oci-region-key eg:IAD>","namespace":"<ocir-namespace>","realm":"oc1|oc2|oc3"}' | ./docker_image_check.sh
input=$(cat)

REGION=$(echo "$input" | jq -r '.region')
REGION_KEY=$(echo "$input" | jq -r '.regionKey')
NAMESPACE=$(echo "$input" | jq -r '.namespace // "iddfxd5j9l2o"')
REALM=$(echo "$input" | jq -r '.realm // "oc1"')

# Build the OCIR registry host for this realm.
# OC1 commercial: <region-key>.ocir.io
# OC2 US Gov / OC3 US DoD: ocir.<region-identifier>.oci.oraclegovcloud.com
if [ "$REALM" == "oc1" ]; then
  HOST=$(echo "$REGION_KEY" | tr '[:upper:]' '[:lower:]')
  REGISTRY="${HOST}.ocir.io"
else
  REGISTRY="ocir.${REGION}.oci.oraclegovcloud.com"
fi

# Get the repository token
TOKEN=$(curl -s "https://${REGISTRY}/20180419/docker/token?service=${REGISTRY}&scope=repository:${NAMESPACE}/oci-datadog-forwarder/logs:pull" | jq -r .token)
URL="https://${REGISTRY}/v2/${NAMESPACE}/oci-datadog-forwarder/logs/manifests/latest"
HTTP_STATUS=$(curl -i -H "Authorization: Bearer $TOKEN" \
-H "Accept: application/vnd.oci.image.index.v1+json" -s -o /dev/null -w "%{http_code}" $URL)

if [[ "$HTTP_STATUS" =~ ^2 ]]; then
  echo "{\"value\": \"$REGION\", \"failure\": \"\"}"
else
  echo "{\"value\": \"$REGION\", \"failure\": \"failed-to-get\"}"
fi
