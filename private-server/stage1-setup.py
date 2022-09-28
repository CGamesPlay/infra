#!/usr/bin/python3
# This script installs the Vault CA certificate and the keyscript.
import pathlib

import requests

r = requests.get("https://vault.service.consul:8200/v1/pki/ca/pem")
r.raise_for_status()
ca_cert = r.text.strip()

keyfile = pathlib.Path("templates/keyscript.py").read_text().strip()

print(
    f"cat <<'EOF' > /usr/local/share/ca-certificates/vault.global.crt\n{ca_cert}\nEOF"
)
print("update-ca-certificates")
print(
    f"cat <<'EOF' > /usr/local/bin/keyscript\n{keyfile}\nEOF\nchmod +x /usr/local/bin/keyscript"
)
