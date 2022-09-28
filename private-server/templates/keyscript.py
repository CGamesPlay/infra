#!/usr/bin/env python3
# This is the keyscript that is executed by stage1. It needs to print the
# decryption key to standard output. Note that a trailing newline in the output
# means that the decryption key has a trailing newline in it; this is probably
# not intended.
#
# This keyscript takes a wrapping token from the cloud-config user data and
# uses it to request the actual decryption key from Vault.
#
#   private-server:
#     token: <string>
import sys

import requests
import yaml

VAULT_URL = "https://vault.cluster.cgamesplay.com"
CA_PATH = "/usr/local/share/ca-certificates/vault.global.crt"

# Allow overriding the filename for testing
filename = "/var/lib/cloud/instance/cloud-config.txt"
if len(sys.argv) > 1:
    filename = sys.argv[1]

try:
    with open(filename) as f:
        result = yaml.safe_load(f)

    config = result["private-server"]
    token = config["token"]
except Exception as e:
    raise ValueError("Unable to retrieve token from user data") from e

resp = requests.post(
    f"{VAULT_URL}/v1/sys/wrapping/unwrap",
    headers={"X-Vault-Token": token},
    verify=CA_PATH,
)
resp.raise_for_status()
json = resp.json()

print(json["data"]["key"], end="")
