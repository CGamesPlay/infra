# Wireguard

## Runbook

### Adding a new client

The WireGuard playbook installs a script called `wg-add-peer` to the master node. This script will add a new peer or print the configuration for an existing one.

Usage: `wg-add-peer peername`

This script automatically assigns an IP to the node and generates keys, then outputs the configuration as well as a QR code.

Note that to actually use most of the services, you will have to add the CA certificate to the peer's trust root. This can be downloaded from <https://vault.service.consul:8200/v1/pki/ca/pem>. On iPhone, you will need to follow the following procedure:

1. [Download the certificate](https://vault.service.consul:8200/v1/pki/ca/pem).
2. In Files, manually rename it to `ca.crt` then tap to install.
3. In Settings, install it using the "Profile Downloaded" option in the main menu.
4. Trust it in Settings > General > About > Certificate Trust Settings.
5. Verify it worked by visiting [Nomad](https://nomad.service.consul:4646/).

