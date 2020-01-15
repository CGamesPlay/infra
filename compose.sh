#!/bin/sh
# This is a simple script to run docker-compose on the target project with the
# correct set of override files. Set CLOUD_ENV to the override file you want to
# use, and the first argument to this program is the project to run in.
# Everything else is passed to docker-compose.

project="$1"
shift
compose_args="-f $project/docker-compose.yml"
if [ -f $project/docker-compose.$CLOUD_ENV.yml ]; then
  compose_args="$compose_args -f $project/docker-compose.$CLOUD_ENV.yml"
fi
exec docker-compose $compose_args "$@"
