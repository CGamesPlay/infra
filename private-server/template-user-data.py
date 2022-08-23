#!/usr/bin/python3

import yaml
import requests
import subprocess
import os
import gzip

def file(path):
    with open(path, 'r') as f:
        return f.read()

def write_file(path, content, permissions):
    compressed = gzip.compress(content.encode('utf-8'))
    encoding = None
    if len(compressed) < len(content):
        content = compressed
        encoding = 'gzip'
    return { 'path': path, 'content': content, 'permissions': permissions, 'encoding': encoding }

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
    'packages': ['docker.io', 'hcloud-cli', 'python3', 'python3-pip'],
    'ca_certs': {
        'trusted': [ca_cert]
    },
    'runcmd': [],
    'write_files': [
        write_file('/usr/local/bin/ps-auto-shutdown', file('ps-auto-shutdown'), '0755'),
        write_file('/usr/local/bin/ps-resize-drive', file('ps-resize-drive'), '0755'),
    ],
}

print('#cloud-config')
print(yaml.dump(user_data), end='')
