#!/bin/bash
set -euo pipefail

export VAULT_CACERT=/opt/vault/server.crt

# Turn on our secrets engines
vault secrets enable -version=1 kv
vault secrets enable pki

# Set up the PKI engine
vault secrets tune -max-lease-ttl=87600h pki
vault write -field certificate pki/root/generate/internal \
    common_name=vault.global \
    ttl=87600h > /usr/local/share/ca-certificates/vault.global.crt
update-ca-certificates
vault secrets tune -max-lease-ttl=8760h pki
vault write pki/config/urls \
    issuing_certificates="https://vault.consul.service:8200/v1/pki/ca" \
    crl_distribution_points="https://vault.consul.service:8200/v1/pki/crl"
vault write pki/roles/server-${DC} \
    allowed_domains=server.${DC}.consul,server.${DC}.nomad,server.${DC}.vault,service.consul \
    allow_bare_domains=true \
    allow_subdomains=true \
    generate_lease=true \
    max_ttl=1440h

# Set up the authentication for vault-agent
vault policy write vault-agent - <<EOF
path "pki/issue/{{identity.entity.name}}" {
  capabilities = ["create", "update"]
}
path "kv/cluster/*" {
  capabilities = ["read"]
}
EOF

vault auth enable cert
cert_accessor=$(vault auth list -format=json | jq -r '.["cert/"].accessor')
# Allow vault to accept its own certificates for auth
vault write auth/cert/certs/self \
    certificate=@/usr/local/share/ca-certificates/vault.global.crt

# Create an entity for this server
vault write identity/entity name=server-${DC} policies=vault-agent
entity_id=$(vault read -field=id identity/entity/name/server-${DC})
vault write identity/entity-alias \
    canonical_id=$entity_id \
    name=server.${DC}.vault \
    mount_accessor=$cert_accessor

# Now that our CA is set up, regenerate our self-signed certificates
# using it.
consul-template -config=/dev/stdin -once <<TEMPLATE_END
template {
    destination = "/opt/vault/server.crt"
    error_on_missing_key = true
    contents = <<EOF
{{ with secret "pki/issue/server-${DC}" "common_name=vault.service.consul" "ip_sans=127.0.0.1" "ttl=1440h"}}
{{ .Data.certificate }}
{{ end }}
EOF
}

template {
    destination = "/opt/vault/server.key"
    error_on_missing_key = true
    contents = <<EOF
{{ with secret "pki/issue/server-${DC}" "common_name=vault.service.consul" "ip_sans=127.0.0.1" "ttl=1440h"}}
{{ .Data.private_key }}
{{ end }}
EOF
}
TEMPLATE_END

service vault reload

# Create the initial vault agent certificates for this machine.
consul-template -config=/dev/stdin -once <<TEMPLATE_END
template {
    destination = "/etc/vault-agent.d/agent.crt"
    error_on_missing_key = true
    contents = <<EOF
{{ with secret "pki/issue/server-${DC}" "common_name=server.${DC}.vault" "ttl=1440h"}}
{{ .Data.certificate }}
{{ end }}
EOF
}

template {
    destination = "/etc/vault-agent.d/agent.key"
    error_on_missing_key = true
    contents = <<EOF
{{ with secret "pki/issue/server-${DC}" "common_name=server.${DC}.vault" "ttl=1440h"}}
{{ .Data.private_key }}
{{ end }}
EOF
}
TEMPLATE_END
