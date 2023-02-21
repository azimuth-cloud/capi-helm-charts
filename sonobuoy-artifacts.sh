#!/bin/bash
set -x 

retries=0
retry_limit=20
while true; do
    result_file=$(sonobuoy retrieve)
    RC=$?
    if [[ ${RC} -eq 0 ]]; then
        break
    fi
    retries=$(( retries + 1 ))
    if [[ ${retries} -eq ${retry_limit} ]]; then
        echo "Retries timed out. Check 'sonobuoy retrieve' command."
        exit 1
    fi
    echo "Error retrieving results. Waiting ${STATUS_INTERVAL_SEC}s to retry...[${retries}/${retry_limit}]"
    sleep "${STATUS_INTERVAL_SEC}"
done

#mkdir ./results && tar xzf $result_file -C ./results

sudo apt install jq -y 

sonobuoy results $tarball --mode=detailed | jq '.' > results.txt
