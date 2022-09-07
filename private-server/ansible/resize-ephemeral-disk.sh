#!/bin/bash
set -xueo pipefail
sgdisk -e -d 4 -N 4 /dev/sda
partprobe
resize2fs /dev/sda4
