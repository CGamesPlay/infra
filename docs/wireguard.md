# Wireguard

## Runbook

### Adding a new client

The following script will help in creating the configuration for a new client. It will need to be run as root to allow adding the new peer to Wireguard, however it requires no other configuration so you can save it to a convenient location like `/root/wg-add-peer.sh`.

Install dependencies:

```bash
apt install qrencode
```

Run this script:

```bash
server_pubkey=$(wg show wg0 public-key)
server_ip=$(curl -sS4 ifconfig.co)
num_peers=$(wg show wg0 peers | wc -l)
client_privkey=$(wg genkey)
client_pubkey=$(echo $client_privkey | wg pubkey)
client_ip=172.30.15.$((num_peers + 1))
cat >/run/client.conf <<EOF
[Interface]
PrivateKey = $client_privkey
Address = $client_ip/20
DNS = 172.30.0.1

[Peer]
PublicKey = $server_pubkey
AllowedIPs = 172.30.0.0/20
Endpoint = $server_ip:51820
EOF
wg set wg0 peer "$client_pubkey" allowed-ips $client_ip/32
wg-quick save /etc/wireguard/wg0.conf
# Send the config somehow, here is an example
qrencode -t ansiutf8 < /run/client.conf
rm /run/client.conf
```

Note that to actually use most of the services, you will have to add the CA certificate to the peer's trust root. This can be downloaded from <https://vault.service.consul:8200/v1/pki/ca/pem>. On iPhone, you will need to follow the following procedure:

1. [Download the certificate](https://vault.service.consul:8200/v1/pki/ca/pem).
2. In Files, manually rename it to `ca.crt` then tap to install.
3. In Settings, install it using the "Profile Downloaded" option in the main menu.
4. Trust it in Settings > General > About > Certificate Trust Settings.
5. Verify it worked by visiting [Nomad](https://nomad.service.consul:4646/).

