#!/bin/bash
# This script runs on the local machine to prepare the data necessary for a new
# cluster. Basically, it creates a bunch of SSL certificates and other secrets,
# then packages them up to be copied to the new machine. We could do this on
# the remote machine directly, but this would require starting up the services
# and gradually upgrading them to be more secure. Using this pattern, we simple
# create a production config locally without using it, and then directly boot
# into a production environment on the remote host.
set -uexo pipefail

DC=nbg1

# Setup data directory {{{

if [ -d data ]; then
    echo "data: directory already exists" >&2
    exit 1
fi
mkdir data
echo DC=${DC} > data/env

# }}}
# Wireguard setup {{{

wg_master_key=$(wg genkey | tee data/wg_master.key)
wg_master_pub=$(echo $wg_master_key | wg pubkey)
wg_local_key=$(wg genkey | tee data/wg_local.key)

cat >data/wg0.conf <<EOF
[Interface]
PrivateKey = $wg_local_key
Address = 172.30.15.1/20

[Peer]
PublicKey = $wg_master_pub
AllowedIPs = 172.30.0.0/20
Endpoint = SERVER_IP_ADDRESS:51820
PersistentKeepalive = 60
EOF

# }}}
# Consul initialization {{{

consul keygen > data/consul-gossip.key
consul agent -datacenter=${DC} -node server-${DC}-bootstrap -config-file=consul.hcl &
consul_pid=$!
while [[ ! $(consul info 2>&1 >/dev/null) == *"Permission denied"* ]]; do sleep 1; done
consul acl bootstrap | tee data/consul-acl.txt
export CONSUL_HTTP_TOKEN=$(cat data/consul-acl.txt | grep 'SecretID' | cut -d: -f2 | xargs)
consul acl set-agent-token agent "$CONSUL_HTTP_TOKEN"
consul acl policy create -name anonymous -rules @consul-policy-anonymous.hcl
consul acl token create -description "Default (anonymous) token" -policy-name anonymous | tee data/anonymous-consul-token.txt
anonymous_consul_token=$(cat data/anonymous-consul-token.txt | grep 'SecretID' | cut -d: -f2 | xargs)
consul acl set-agent-token default "$anonymous_consul_token"
consul acl policy create -name vault -rules @consul-policy-vault.hcl
consul acl token create -description "Vault token" -policy-name vault | tee data/vault-consul-token.txt

# }}}
# Nomad initialization {{{

nomad operator keygen > data/nomad-gossip.key

# }}}
# Vault initialization {{{

export VAULT_ADDR="http://127.0.0.1:8200"
vault_consul_token=$(cat data/vault-consul-token.txt | grep 'SecretID' | cut -d: -f2 | xargs)
CONSUL_HTTP_TOKEN=$vault_consul_token vault server -config=vault.hcl &
vault_pid=$!
while [[ ! $(vault status) == *Sealed*true* ]]; do sleep 1; done
vault operator init -key-shares 1 -key-threshold 1 | tee data/vault-root-keys.txt
export VAULT_TOKEN=$(cat data/vault-root-keys.txt | grep "Initial Root Token" | cut -d: -f2)
vault_unseal_key=$(cat data/vault-root-keys.txt | grep "Unseal Key 1" | cut -d: -f2)
vault operator unseal "$vault_unseal_key"

# }}}
# Vault PKI setup {{{

# mTLS is required for a few reasons if there will be untrusted workloads on
# the cluster.
#
# - Consul - if mTLS is disabled, a malicious workload could masquerade as a
#   Consul server and modify the catalog as desired, allowing it to further
#   masquerade as any other service.
# - Nomad - if mTLS is disabled, a malicious workload could masquerade as a
#   Nomad server and schedule arbitrary workloads on the cluster.
#
# Even if Consul and Nomad are secured with mTLS, malicious workloads with root
# privileges on a node have the capacity to interfere with other workloads on
# that node. Worse, a malicious workloads with root privileges running on a
# server node has the capacity to hijack Nomad, Consul, or even Vault,
# effectively giving it full control over the entire cluster. To properly
# handle this circumstance, no privileged workloads can be allowed to run on
# server nodes.

# This is basically required reading for Vault PKI
# https://www.vaultproject.io/docs/secrets/pki
# And consul-specific stuff:
# https://learn.hashicorp.com/tutorials/consul/vault-pki-consul-secure-tls

vault secrets enable pki
vault secrets tune -max-lease-ttl=8760h pki
vault write -field certificate pki/root/generate/internal \
    common_name=global.vault \
    ttl=8760h > data/ca.crt
# XXX - URLs here should be on vault.service.consul, and https?
vault write pki/config/urls \
    issuing_certificates="http://127.0.0.1:8200/v1/pki/ca" \
    crl_distribution_points="http://127.0.0.1:8200/v1/pki/crl"
vault write pki/roles/server-${DC} \
    allowed_domains=server.${DC}.consul,server.${DC}.nomad,service.consul \
    allow_bare_domains=true \
    allow_subdomains=true \
    generate_lease=true \
    max_ttl=720h
vault write -format=json pki/issue/server-${DC} \
    common_name=server.${DC}.consul \
    alt_names=consul.service.consul \
    ip_sans=127.0.0.1 \
    ttl=720h > data/consul-server-cert.json
cat data/consul-server-cert.json | jq -r .data.certificate \
    > data/server.${DC}.consul.crt
cat data/consul-server-cert.json | jq -r .data.private_key \
    > data/server.${DC}.consul.key
vault write -format=json pki/issue/server-${DC} \
    common_name=server.${DC}.nomad \
    alt_names=nomad.service.consul \
    ip_sans=127.0.0.1 \
    ttl=720h > data/nomad-server-cert.json
cat data/nomad-server-cert.json | jq -r .data.certificate \
    > data/server.${DC}.nomad.crt
cat data/nomad-server-cert.json | jq -r .data.private_key \
    > data/server.${DC}.nomad.key
vault write -format=json pki/issue/server-${DC} \
    common_name=vault.service.consul \
    ip_sans=127.0.0.1 \
    ttl=720h > data/vault-server-cert.json
cat data/vault-server-cert.json | jq -r .data.certificate \
    > data/vault.service.consul.crt
cat data/vault-server-cert.json | jq -r .data.private_key \
    > data/vault.service.consul.key

# }}}
# Shutdown and create snapshot {{{

vault operator step-down
kill $vault_pid
wait $vault_pid

consul leave
wait $consul_pid
tar -cf data/consul.tar -C data/consul .

# }}}

# vim:foldmethod=marker
