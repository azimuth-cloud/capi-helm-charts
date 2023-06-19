#!/bin/bash

set -e

#####
# This script wraps sonobuoy retrieve with a retry
#
# https://github.com/vmware-tanzu/sonobuoy/issues/1633#issuecomment-1112667471
#####


retries=0
retry_limit=20
while true; do
    result_file=$(sonobuoy retrieve "$@")
    RC=$?
    if [[ ${RC} -eq 0 ]]; then
        break
    fi
    retries=$(( retries + 1 ))
    if [[ ${retries} -eq ${retry_limit} ]]; then
        echo "Retries timed out. Check 'sonobuoy retrieve' command."
        exit 1
    fi
    echo "Error retrieving results. Waiting 30s to retry...[${retries}/${retry_limit}]"
    sleep 30
done
