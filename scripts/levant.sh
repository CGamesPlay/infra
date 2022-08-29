#!/bin/bash
set -ueo pipefail
shopt -s extglob

operation=$1
shift
n_error=0

JOBS=${@:-nomad/!(*.disabled)}
for job in $JOBS; do
    job=$(basename "$job")
    echo $job
    cd "nomad/$job"
    if ! levant $operation -ignore-no-changes; then
        ((++n_error))
    fi
    cd ../..
    echo
done

exit $n_error
