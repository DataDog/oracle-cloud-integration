#!/bin/bash

# Prompt once for credentials and image tag
echo "Getting details for building the images in your repo. Make sure you have:
  1. oci cli installed and cofigured for your tenancy
  2. jq installed
  3. access to push images to tenancy
  4. You tenancy in every region has the registry created with the names: oci-datadog-forwarder/metrics, oci-datadog-forwarder/logs and oci-datadog-forwarder/events
  5. Docker buildx is installed.
"

echo "Supported realms (registry host is auto-detected from the region identifier):
  - OC1 commercial      (e.g. us-ashburn-1, us-phoenix-1)        -> <region-key>.ocir.io
  - OC2 US Gov/FedRAMP  (e.g. us-langley-1, us-luke-1)             -> ocir.<region>.oci.oraclegovcloud.com
  - OC3 US DoD          (e.g. us-gov-ashburn-1, us-gov-chicago-1)  -> ocir.<region>.oci.oraclegovcloud.com
  - OC4 UK Sovereign    (e.g. uk-gov-london-1)                     -> ocir.<region>.oci.oraclegovcloud.uk
"

read -p "Enter Docker username: " USERNAME
read -p "Enter tenancy namespace: " NAMESPACE
read -s -p "Enter Docker password: " PASSWORD
echo
read -p "Enter Docker image tag (e.g., v1.0.0): " TAG
read -p "Enter regions (comma-separated, e.g., us-phoenix-1,us-ashburn-1) or press Enter for all regions: " REGION_INPUT

# ---------------------------------------------------------------------------
# Realm -> OCIR registry host mapping.
# Commercial (OC1) registries use the short 3-letter region key:
#   <region-key>.ocir.io   e.g. iad.ocir.io
# Government / Defense / Sovereign realms use the full region identifier:
#   ocir.<region-identifier>.<realm-domain>
#   e.g. ocir.us-langley-1.oci.oraclegovcloud.com        (OC2)
#        ocir.us-gov-ashburn-1.oci.oraclegovcloud.com    (OC3)
#        ocir.uk-gov-london-1.oci.oraclegovcloud.uk      (OC4)
# ---------------------------------------------------------------------------
declare -A GOV_REGION_DOMAIN=(
  ["us-langley-1"]="oci.oraclegovcloud.com"
  ["us-luke-1"]="oci.oraclegovcloud.com"
  ["us-gov-ashburn-1"]="oci.oraclegovcloud.com"
  ["us-gov-chicago-1"]="oci.oraclegovcloud.com"
  ["us-gov-phoenix-1"]="oci.oraclegovcloud.com"
  ["uk-gov-london-1"]="oci.oraclegovcloud.uk"
  ["uk-gov-cardiff-1"]="oci.oraclegovcloud.uk"
)

# registry_host_for <region_identifier> <region_key>
# Echoes the OCIR registry host (no trailing slash, lowercase) for the region.
registry_host_for() {
  local region_id="$1"
  local region_key="$2"
  if [[ -n "${GOV_REGION_DOMAIN[$region_id]}" ]]; then
    echo "ocir.${region_id}.${GOV_REGION_DOMAIN[$region_id]}"
  else
    echo "$(echo "$region_key" | tr '[:upper:]' '[:lower:]').ocir.io"
  fi
}

# Process region input and fetch region subscriptions from OCI.
# We keep both the region identifier (region-name, e.g. us-ashburn-1) and the
# short region key (region-key, e.g. IAD) because the registry host format
# differs by realm: commercial uses the key, gov/dod uses the identifier.
REGIONS_JSON=$(oci iam region-subscription list)
if [ -n "$REGION_INPUT" ]; then
  REGION_FILTER=$(echo "$REGION_INPUT" | sed 's/[[:space:]]*,[[:space:]]*/","/g' | sed 's/^/["/' | sed 's/$/"]/')
  echo "Filtering for regions: $REGION_INPUT"
  REGIONS_JSON=$(echo "$REGIONS_JSON" | jq -c --argjson regions "$REGION_FILTER" '.data[] | select(."region-name" as $name | $regions | index($name))')
else
  echo "No specific regions provided. Using all available regions."
  REGIONS_JSON=$(echo "$REGIONS_JSON" | jq -c '.data[]')
fi

# Parallel arrays: region identifiers and region keys, indexed identically.
REGION_IDS=($(echo "$REGIONS_JSON" | jq -r '."region-name"'))
REGION_KEYS=($(echo "$REGIONS_JSON" | jq -r '."region-key"'))

# Check if any regions were found
if [ ${#REGION_IDS[@]} -eq 0 ]; then
  echo "No subscribed regions found. Exiting."
  exit 1
fi

# Display the computed registry host for each region so the user can verify
# the realm detection before pushing.
echo "Image will be built in following regions:"
for i in "${!REGION_IDS[@]}"; do
  echo "  - ${REGION_IDS[$i]} (host: $(registry_host_for "${REGION_IDS[$i]}" "${REGION_KEYS[$i]}"))"
done

# Prompt for confirmation
read -p "Do you want to continue with building and pushing images? (y/n): " CONFIRMATION

# Convert input to lowercase for flexible handling
CONFIRMATION=$(echo "$CONFIRMATION" | tr '[:upper:]' '[:lower:]')

if [[ "$CONFIRMATION" != "y" && "$CONFIRMATION" != "yes" ]]; then
  echo "Operation canceled by user."
  unset PASSWORD
  exit 0
fi

# Ensure buildx is initialized
docker buildx create --use --name multiarch-builder >/dev/null 2>&1 || docker buildx use multiarch-builder

FAILED_ITEMS=()

build_and_push_image() {
  IMAGE_PATH=$1
  REGISTRY=$2
  TAG=$3
  DOCKER_FILE=$4
  echo "Building and pushing multi-arch image ${IMAGE_PATH} to $REGISTRY..."
  docker buildx build -f ${DOCKER_FILE} \
    --platform linux/amd64,linux/arm64 \
    --tag "${IMAGE_PATH}:${TAG}" \
    --tag "${IMAGE_PATH}:latest" \
    --push \
    .

  if [ $? -eq 0 ]; then
    echo "Successfully built and pushed ${IMAGE_PATH}:${TAG} and :latest"
  else
    echo "############################################################"
    echo "## FAILED to build and push image for $IMAGE_PATH"
    echo "############################################################"
    FAILED_ITEMS+=("$IMAGE_PATH")
  fi
}

# Loop through each subscribed region (identifier + key in parallel)
for i in "${!REGION_IDS[@]}"; do
  REGION_ID="${REGION_IDS[$i]}"
  REGION_KEY="${REGION_KEYS[$i]}"
  REGISTRY=$(registry_host_for "$REGION_ID" "$REGION_KEY")
  LOGIN_USER="${NAMESPACE}/${USERNAME}"
  IMAGE_PATH_METRICS="${REGISTRY}/${NAMESPACE}/oci-datadog-forwarder/metrics"
  IMAGE_PATH_LOGS="${REGISTRY}/${NAMESPACE}/oci-datadog-forwarder/logs"
  IMAGE_PATH_EVENTS="${REGISTRY}/${NAMESPACE}/oci-datadog-forwarder/events"

  echo "Metrics image: $IMAGE_PATH_METRICS"
  echo "Logs image: $IMAGE_PATH_LOGS"
  echo "Events image: $IMAGE_PATH_EVENTS"

  echo "Logging in to $REGISTRY..."
  echo "$PASSWORD" | docker login "$REGISTRY" --username "$LOGIN_USER" --password-stdin
  if [ $? -ne 0 ]; then
    echo "############################################################"
    echo "## LOGIN FAILED for $REGISTRY"
    echo "############################################################"
    FAILED_ITEMS+=("login:$REGISTRY")
    continue
  fi

  build_and_push_image "$IMAGE_PATH_METRICS" "$REGISTRY" "$TAG" "Dockerfile-metrics"
  build_and_push_image "$IMAGE_PATH_LOGS" "$REGISTRY" "$TAG" "Dockerfile-logs"
  build_and_push_image "$IMAGE_PATH_EVENTS" "$REGISTRY" "$TAG" "Dockerfile-events"
done

# Clear the password from memory
unset PASSWORD

if [ ${#FAILED_ITEMS[@]} -gt 0 ]; then
  echo ""
  echo "############################################################"
  echo "## BUILD/PUSH COMPLETED WITH FAILURES:"
  for ITEM in "${FAILED_ITEMS[@]}"; do
    echo "##   - $ITEM"
  done
  echo "############################################################"
  exit 1
fi

echo "All images built and pushed successfully in all regions."
