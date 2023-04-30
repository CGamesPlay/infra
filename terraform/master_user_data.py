#!/usr/bin/python3
# This script generates the user data used to spin up the master instance. It
# is called by Terraform.

import json
import yaml
import requests
import subprocess
import os
import sys
import gzip

ssh_keys = subprocess.run(["ssh-add", "-L"], capture_output=True, check=True).stdout.decode('utf-8').splitlines()

drive_script = """
set -ex
mkdir -p /opt
echo "UUID=$(lsblk /dev/sdb -no uuid) /opt ext4 discard,defaults,errors=remount-ro 0 2" >> /etc/fstab
mount -a
"""

user_data = {
    'disable_root': True,
    'user': {
        'name': 'ubuntu',
        'groups': ['adm', 'docker'],
        'ssh_authorized_keys': ssh_keys,
        'sudo': 'ALL=(ALL) NOPASSWD:ALL',
    },
    'users': {
        'name': 'root',
        'lock_passwd': True,
    },
    'ntp': {
        'enabled': True,
    },
    'timezone': 'UTC',
    'package_update': True,
    'packages': ['docker.io', 'wireguard', 'net-tools', 'jq'],
    'runcmd': [ drive_script, 'chage -E -1 -M -1 -d -1 root' ],
}

result = "#cloud-config\n" + yaml.dump(user_data)
if sys.stdout.isatty():
    print(result, end='')
else:
    print(json.dumps({ "rendered": result }))
