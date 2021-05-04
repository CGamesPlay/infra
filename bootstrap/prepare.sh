#!/bin/bash
# This script runs on the local machine to prepare the data necessary for a new
# cluster. Basically, it creates a bunch of SSL certificates and other secrets,
# then packages them up to be copied to the new machine. We could do this on
# the remote machine directly, but this would require starting up the services
# and gradually upgrading them to be more secure. Using this pattern, we simple
# create a production config locally without using it, and then directly boot
# into a production environment on the remote host.
set -uexo pipefail

DC=eu-central-1

# Setup data directory {{{

if [ -d data ]; then
    echo "data: directory already exists" >&2
    exit 1
fi
mkdir data
echo DC=${DC} > data/env

# }}}
# Consul initialization {{{

consul agent -datacenter=${DC} -node server-${DC}-bootstrap -config-file=consul.hcl & sleep 10
consul_pid=$!
consul acl bootstrap | tee data/consul-acl.txt
export CONSUL_HTTP_TOKEN=$(cat data/consul-acl.txt | grep 'SecretID' | cut -d: -f2 | xargs)
consul acl set-agent-token default "$CONSUL_HTTP_TOKEN"
consul acl policy create -name vault -rules @consul-policy-vault.hcl
consul acl token create -description "Vault token" -policy-name vault | tee data/vault-consul-token.txt

# }}}
# Vault initialization {{{

export VAULT_ADDR="http://127.0.0.1:8200"
vault_consul_token=$(cat data/vault-consul-token.txt | grep 'SecretID' | cut -d: -f2 | xargs)
CONSUL_HTTP_TOKEN=$vault_consul_token vault server -config=vault.hcl & sleep 5
vault_pid=$!
vault operator init -key-shares 1 -key-threshold 1 | tee data/vault-root-keys.txt
export VAULT_TOKEN=$(cat data/vault-root-keys.txt | grep "Initial Root Token" | cut -d: -f2)
vault_unseal_key=$(cat data/vault-root-keys.txt | grep "Unseal Key 1" | cut -d: -f2)
vault operator unseal "$vault_unseal_key"

# }}}
# Vault PKI setup {{{

# I've opted against mTLS for this cluster, since it doesn't really provide any
# benefit in a cluster of this size (most operating in one machine or only a
# single AZ). In the future, before investigating mTLS, I also want to consider
# using Wireguard to secure communication, since this might be easier and lower
# overhead than mTLS.
: <<'MTLS_DISABLED'

# This is basically required reading for Vault PKI
# https://www.vaultproject.io/docs/secrets/pki
# And consul-specific stuff:
# https://learn.hashicorp.com/tutorials/consul/vault-pki-consul-secure-tls

vault secrets enable pki
vault secrets tune -max-lease-ttl=8760h pki
vault write -field certificate pki/root/generate/internal \
    common_name=global.consul ttl=8760h \
    > data/global.consul.crt
# XXX - URLs here should be on vault.service.consul, and https?
vault write pki/config/urls \
    issuing_certificates="http://127.0.0.1:8200/v1/pki/ca" \
    crl_distribution_points="http://127.0.0.1:8200/v1/pki/crl"
vault write pki/roles/consul-${DC} \
    allowed_domains=${DC}.consul \
    allow_subdomains=true \
    generate_lease=true \
    max_ttl=720h
MTLS_DISABLED

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
