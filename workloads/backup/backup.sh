#!/bin/sh
set -uex
apk update
apk add restic
restic version
restic backup --verbose /var/lib/rancher --exclude-caches -o s3.storage-class=STANDARD_IA
