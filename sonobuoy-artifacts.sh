#!/bin/bash
set -x 

retries=0
retry_limit=10
while true; do
    result_file=$(sonobuoy retrieve)
    RC=$?
    if [[ ${RC} -eq 0 ]]; then
        break
    fi
    retries=$(( retries + 1 ))
    if [[ ${retries} -eq ${retry_limit} ]]; then
        log_info "Retries timed out. Check 'sonobuoy retrieve' command."
        exit 1
    fi
    log_info "Error retrieving results. Waiting ${STATUS_INTERVAL_SEC}s to retry...[${retries}/${retry_limit}]"
    sleep "${STATUS_INTERVAL_SEC}"
done

output=$(sonobuoy retrieve --kubeconfig kubeconfig) && mkdir ./results; tar xzf $output -C ./results