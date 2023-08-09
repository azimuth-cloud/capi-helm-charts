#!/usr/bin/env bash

set -ex

#####
# This script waits for a FIP to become available for allocation
#####


# Default the GITHUB_OUTPUT to stdout
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/stdout}"

# If not floating IP network is given, use the first one marked external
if [ -z "$FLOATING_IP_NETWORK" ]; then
  FLOATING_IP_NETWORK="$(openstack network list --external -c Name -f value | head -1)"
fi

# Wait until we are able to allocate a FIP
FLOATING_IP=
until \
  FLOATING_IP="$(
    openstack floating ip create \
      -f value \
      -c floating_ip_address \
      --description "Reserved for capi-helm-charts CI run $GITHUB_RUN_ID" \
      "$FLOATING_IP_NETWORK"
  )"
do
  sleep 30
done

# Output the discovered IP
echo "floating-ip=${FLOATING_IP}" >> "$GITHUB_OUTPUT"
