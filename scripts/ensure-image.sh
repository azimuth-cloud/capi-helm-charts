#!/usr/bin/env bash

set -ex

#####
# This script uploads an image to OpenStack unless already present
#####


[ -z "$IMAGE_NAME" ] && echo "IMAGE_NAME is required" >&2 && exit 1
[ -z "$IMAGE_URL" ] && echo "IMAGE_URL is required" >&2 && exit 1

# Default the GITHUB_OUTPUT to stdout
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/stdout}"

# Try to find the ID of an existing image with the required name
#   NOTE: This command is allowed/expected to fail sometimes
IMAGE_ID="$(openstack image show -f value -c id "$IMAGE_NAME" || true)"

# If there is an existing image, we are done
if [ -n "$IMAGE_ID" ]; then
    echo "image-id=${IMAGE_ID}" >> "$GITHUB_OUTPUT"
    exit
fi

# If not, download the image and upload it to Glance
IMAGE_FNAME="${IMAGE_NAME}.${IMAGE_DISK_FORMAT:-qcow2}"
curl -Lo "$IMAGE_FNAME" --progress-bar "$IMAGE_URL"
IMAGE_ID="$(
  openstack image create \
    --progress \
    --private \
    --container-format "${IMAGE_CONTAINER_FORMAT:-bare}" \
    --disk-format "${IMAGE_DISK_FORMAT:-qcow2}" \
    --file "$IMAGE_FNAME" \
    --property hw_scsi_model=virtio-scsi \
    --property hw_disk_bus=scsi \
    --format value \
    --column id \
    "$IMAGE_NAME"
)"
echo "image-id=${IMAGE_ID}" >> "$GITHUB_OUTPUT"
