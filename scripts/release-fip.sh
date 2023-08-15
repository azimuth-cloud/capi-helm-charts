#!/usr/bin/env bash

set -ex

#####
# This script releases a FIP if one is defined
#####


FLOATING_IP="$1"

if [ -n "$FLOATING_IP" ]; then
  openstack floating ip delete "$FLOATING_IP" || true
fi
