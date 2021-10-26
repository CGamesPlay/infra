#!/bin/bash
set -ueio pipefail
shopt -s extglob

operation=$1
shift

JOBS=${@:-nomad/!(*.disabled)}
for job in $JOBS; do
    job=$(basename "$job")
    echo $job
    (
        cd "nomad/$job"
        levant $operation -ignore-no-changes
    )
    echo
done
