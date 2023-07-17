#!/usr/bin/env bash

set -e

#####
# This script reads dependencies and converts them to GitHub outputs
#####

GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/stdout}"

for dep in $(jq -r '. | keys[]' ./dependencies.json); do
    echo "$dep=$(jq -r ".[\"$dep\"]" ./dependencies.json)" >> "$GITHUB_OUTPUT"
done
