#!/bin/bash

# Prompt once for credentials and image tag
echo "Getting details for building the images in your repo. Make sure you have:
  1. oci cli installed and cofigured for your tenancy
  2. jq installed
  3. access to push images to tenancy
  4. You tenancy in every region has the registry created with the names: oci-datadog-forwarder/metrics and oci-datadog-forwarder/logs
  5. Docker buildx is installed.
"

read -p "Enter Docker username: " USERNAME
read -p "Enter tenancy namespace: " NAMESPACE
read -s -p "Enter Docker password: " PASSWORD
echo
read -p "Enter Docker image tag (e.g., v1.0.0): " TAG
read -p "Enter regions (comma-separated, e.g., us-phoenix-1,us-ashburn-1) or press Enter for all regions: " REGION_INPUT

# Process region input and fetch region keys from OCI
if [ -n "$REGION_INPUT" ]; then
  # Convert comma-separated input to jq array format and filter regions
  REGION_FILTER=$(echo "$REGION_INPUT" | sed 's/[[:space:]]*,[[:space:]]*/","/g' | sed 's/^/["/' | sed 's/$/"]/')
  echo "Filtering for regions: $REGION_INPUT"
  BUILD_TARGETS=($(oci iam region-subscription list | jq -r --argjson regions "$REGION_FILTER" '.data[] | select(.["region-name"] as $name | $regions | index($name)) | .["region-key"]'))
else
  echo "No specific regions provided. Using all available regions."
  BUILD_TARGETS=($(oci iam region-subscription list | jq -r '.data[]."region-key"'))
fi

# Check if any regions were found
if [ ${#BUILD_TARGETS[@]} -eq 0 ]; then
  echo "No region keys found. Exiting."
  exit 1
fi

echo "Image will be built in following regions: ${BUILD_TARGETS[@]}"

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
    echo "Failed to build and push image for $IMAGE_PATH"
  fi
}

# Loop through each region key
for TARGET in "${BUILD_TARGETS[@]}"; do
  TARGET=$(echo "$TARGET" | tr '[:upper:]' '[:lower:]')
  REGISTRY="${TARGET}.ocir.io"  # Convert region key to lowercase
  LOGIN_USER="${NAMESPACE}/${USERNAME}"
  IMAGE_PATH_METRICS="${REGISTRY}/${NAMESPACE}/oci-datadog-forwarder/metrics"
  IMAGE_PATH_LOGS="${REGISTRY}/${NAMESPACE}/oci-datadog-forwarder/logs"

  echo "Metrics image: $IMAGE_PATH_METRICS"
  echo "Logs image: $IMAGE_PATH_LOGS"

  echo "Logging in to $REGISTRY..."
  echo "$PASSWORD" | docker login "$REGISTRY" --username "$LOGIN_USER" --password-stdin
  if [ $? -ne 0 ]; then
    echo "Login failed for $REGISTRY"
    continue
  fi
  
  build_and_push_image "$IMAGE_PATH_METRICS" "$REGISTRY" "$TAG" "Dockerfile-metrics"
  build_and_push_image "$IMAGE_PATH_LOGS" "$REGISTRY" "$TAG" "Dockerfile-logs"
done

# Clear the password from memory
unset PASSWORD
