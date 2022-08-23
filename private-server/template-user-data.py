#!/usr/bin/python3

import yaml
import requests
import subprocess
import os

r = requests.get('https://vault.service.consul:8200/v1/pki/ca/pem')
r.raise_for_status()
ca_cert = r.text

ssh_keys = subprocess.run(["ssh-add", "-L"], capture_output=True, check=True).stdout.decode('utf-8').splitlines()

user_data = {
    'resize_rootfs': False,
    'growpart': {
        'mode': 'off',
    },
    'disable_root': True,
    'user': {
        'name': 'ubuntu',
        'groups': ['docker'],
        'ssh_authorized_keys': ssh_keys,
        'sudo': 'ALL=(ALL) NOPASSWD:ALL',
    },
    'ntp': {
        'enabled': True,
    },
    'package_update': True,
    'packages': ['docker.io'],
    'ca_certs': {
        'trusted': [ca_cert]
    },
}

print('#cloud-config')
print(yaml.dump(user_data), end='')
