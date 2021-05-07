#!/bin/bash
# This script is a wrapper which generates a script that can be run on the
# master machine to configure Consul, Vault, and Nomad. It's intended to be
# piped directly into an SSH command, like this:
#
#  ./generate_installer.sh | ssh my.master.node -- sudo bash
set -ueo pipefail
echo '#!/bin/bash'
echo 'set -uexo pipefail'
echo

# Preparation {{{

if [ ! -d data ]; then
    echo "data: not a directory" >&2
    exit 1
fi
. data/env

function emit_tee() {
    echo "tee $@ <<'EMIT_TEE' >/dev/null"
    # We use awk here instead of cat to verify that all files end in newlines.
    awk 1
    echo "EMIT_TEE"
    echo
}

function emit_file() {
    echo 'base64 -d <<EOF | gunzip -c >'$2
    gzip -c $1 | base64 -b 100
    echo 'EOF'
}

export VAULT_TOKEN=$(cat data/vault-root-keys.txt | grep "Initial Root Token" | cut -d: -f2 | xargs)
consul_root_token=$(cat data/consul-acl.txt | grep 'SecretID' | cut -d: -f2 | xargs)
vault_root_token=$(cat data/vault-root-keys.txt | grep "Initial Root Token" | cut -d: -f2)
vault_unseal_key=$(cat data/vault-root-keys.txt | grep "Unseal Key 1" | cut -d: -f2 | xargs)
vault_consul_token=$(cat data/vault-consul-token.txt | grep 'SecretID' | cut -d: -f2 | xargs)
wireguard_ip=172.30.0.1
echo 'instance_id=$(hostname)'
cat data/ca.crt | emit_tee /etc/ssl/certs/global.vault.crt
echo

# }}}
# Wireguard {{{

emit_tee /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = $wireguard_ip/20
SaveConfig = true
ListenPort = 51820
PrivateKey = $(cat data/wg_master.key)
PostUp = iptables -A FORWARD -i %i -j ACCEPT
Postup = iptables -t nat -A POSTROUTING -o IFACE_NAME -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o IFACE_NAME -j MASQUERADE
EOF

cat <<'SCRIPT_END'
sed -i 's/IFACE_NAME/'$(ip -o -4 route show to default | awk '{print $5}')'/g' /etc/wireguard/wg0.conf
sed -i 's/.*net\.ipv4\.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -p
ufw allow 51820/udp
systemctl enable --now wg-quick@wg0
SCRIPT_END
echo "wg set wg0 peer '$(cat data/wg_local.key | wg pubkey)' allowed-ips 172.30.15.1/32"
echo

# }}}
# Consul {{{

echo 'chmod 750 /opt/consul /etc/consul.d'
cat data/server.${DC}.consul.crt | emit_tee /opt/consul/agent.crt
cat data/server.${DC}.consul.key | emit_tee /opt/consul/agent.key
echo

echo 'echo node_name = \"server-$instance_id\" > /etc/consul.d/consul.hcl'
echo 'echo encrypt = "'$(cat data/consul-gossip.key)'"'
emit_tee -a /etc/consul.d/consul.hcl <<EOF
datacenter = "${DC}"
data_dir = "/opt/consul"
verify_incoming_rpc = true
verify_outgoing = true
verify_server_hostname = true
ca_file = "/etc/ssl/certs/global.vault.crt"
cert_file = "/opt/consul/agent.crt"
key_file = "/opt/consul/agent.key"

acl {
  enabled = true
  default_policy = "deny"
  enable_token_persistence = true
}

ports {
  https = 8501
}
EOF

# Recommend using https://github.com/hashicorp/go-sockaddr to debug the
# bind_addr template string.
emit_tee /etc/consul.d/server.hcl <<'EOF'
server = true
bootstrap_expect = 1
ui_config {
  enabled = true
}
bind_addr = "{{GetPrivateInterfaces | include \"name\" \"wg0\" | attr \"address\"}}"
EOF

emit_tee /etc/consul.d/client.hcl <<'EOF'
client_addr = "127.0.0.1 {{GetPrivateInterfaces | include \"name\" \"wg0\" | attr \"address\"}}"

ports = {
    dns = 53
}
EOF

emit_tee /etc/systemd/system/consul.service <<'EOF'
[Unit]
Description="HashiCorp Consul - A service mesh solution"
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/consul.d/consul.hcl

[Service]
Type=exec
User=consul
Group=consul
ExecStart=/usr/bin/consul agent -config-dir=/etc/consul.d/
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGTERM
Restart=on-failure
LimitNOFILE=65536
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

emit_tee -a /etc/systemd/resolved.conf <<'EOF'
DNS=127.0.0.1
Domains=~consul
EOF

# }}}
# Vault {{{

echo 'chmod 750 /opt/vault /etc/vault.d'
echo 'rm -rf /opt/vault/*'
cat data/vault.service.consul.crt | emit_tee /opt/vault/agent.crt
cat data/vault.service.consul.key | emit_tee /opt/vault/agent.key
echo

emit_tee /etc/vault.d/vault.hcl <<EOF
ui = true
api_addr = "https://$wireguard_ip:8200/"

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/opt/vault/agent.crt"
  tls_key_file  = "/opt/vault/agent.key"
}

storage "consul" {
  address = "127.0.0.1:8501"
  scheme = "https"
  path = "vault/"
  token = "$vault_consul_token"

  tls_ca_file = "/etc/ssl/certs/global.vault.crt"
}
EOF

emit_tee /etc/systemd/system/vault.service <<'EOF'
[Unit]
Description="HashiCorp Vault - A tool for managing secrets"
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target consul.service
Requires=consul.service
ConditionFileNotEmpty=/etc/vault.d/vault.hcl
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF

cat <<'SCRIPT_END'
export VAULT_ADDR=https://127.0.0.1:8200
sed -i '/^VAULT_ADDR=/d' /etc/environment
echo VAULT_ADDR=$VAULT_ADDR >> /etc/environment

SCRIPT_END

# }}}
# Vault Agent {{{

echo 'mkdir --parents /etc/vault-agent.d'
echo 'chmod 750 /etc/vault-agent.d'
cat data/vault-agent.crt | emit_tee /etc/vault-agent.d/agent.crt
cat data/vault-agent.key | emit_tee /etc/vault-agent.d/agent.key
echo

emit_tee /usr/local/bin/cert-validity-secs <<'END_FILE'
#!/bin/bash
# Returns the number of seconds until the passedd certificate will expire.
set -ueo pipefail
expires=$(date -d "$(openssl x509 -in "$1" -dates -noout | grep notAfter | cut -d= -f2)" +%s)
now=$(date +%s)
echo $(( expires - now))
END_FILE
echo 'chmod +x /usr/local/bin/cert-validity-secs'
echo

emit_tee /etc/vault-agent.d/rotate-certificates.hcl <<END_FILE
vault {
    address = "https://127.0.0.1:8200/"
    ca_cert = "/etc/ssl/certs/global.vault.crt"
    client_cert = "/etc/vault-agent.d/agent.crt"
    client_key = "/etc/vault-agent.d/agent.key"
}

auto_auth {
    method "cert" {}
}

template {
    destination = "/etc/ssl/certs/global.vault.crt"
    error_on_missing_key = true
    contents = <<EOF
{{ with secret "pki/cert/ca"}}
{{ .Data.certificate }}
{{ end }}
EOF
}

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

template {
    destination = "/opt/vault/agent.crt"
    error_on_missing_key = true
    contents = <<EOF
{{ with secret "pki/issue/server-${DC}" "common_name=vault.service.consul" "ip_sans=127.0.0.1" "ttl=1440h"}}
{{ .Data.certificate }}
{{ end }}
EOF
}

template {
    destination = "/opt/vault/agent.key"
    error_on_missing_key = true
    contents = <<EOF
{{ with secret "pki/issue/server-${DC}" "common_name=vault.service.consul" "ip_sans=127.0.0.1" "ttl=1440h"}}
{{ .Data.private_key }}
{{ end }}
EOF
}

template {
    destination = "/opt/consul/agent.crt"
    error_on_missing_key = true
    contents = <<EOF
{{ with secret "pki/issue/server-${DC}" "common_name=server.${DC}.consul" "alt_names=localhost,consul.service.consul" "ip_sans=127.0.0.1" "ttl=1440h"}}
{{ .Data.certificate }}
{{ end }}
EOF
}

template {
    destination = "/opt/consul/agent.key"
    error_on_missing_key = true
    contents = <<EOF
{{ with secret "pki/issue/server-${DC}" "common_name=server.${DC}.consul" "alt_names=localhost,consul.service.consul" "ip_sans=127.0.0.1" "ttl=1440h"}}
{{ .Data.private_key }}
{{ end }}
EOF
}

template {
    destination = "/opt/nomad/agent.crt"
    error_on_missing_key = true
    contents = <<EOF
{{ with secret "pki/issue/server-${DC}" "common_name=server.${DC}.nomad" "alt_names=localhost,nomad.service.consul" "ip_sans=127.0.0.1" "ttl=1440h"}}
{{ .Data.certificate }}
{{ end }}
EOF
}

template {
    destination = "/opt/nomad/agent.key"
    error_on_missing_key = true
    contents = <<EOF
{{ with secret "pki/issue/server-${DC}" "common_name=server.${DC}.nomad" "alt_names=localhost,nomad.service.consul" "ip_sans=127.0.0.1" "ttl=1440h"}}
{{ .Data.private_key }}
{{ end }}
EOF
}
END_FILE

emit_tee /etc/cron.monthly/rotate-certificates <<EOF
#!/bin/bash
# This script periodically runs vault-agent to rotate TLS certificates.
set -ueo pipefail

vault agent -config=/etc/vault-agent.d/rotate-certificates.hcl -exit-after-auth
service vault reload || true
service consul reload || true
service nomad reload || true
EOF
echo 'chmod +x /etc/cron.monthly/rotate-certificates'
echo

# }}}
# Nomad {{{

echo 'chmod 750 /opt/nomad /etc/nomad.d'
echo 'rm -df /opt/nomad/data'
echo

echo 'echo name = \"$instance_id\" > /etc/nomad.d/nomad.hcl'
emit_tee -a /etc/nomad.d/nomad.hcl <<EOF
datacenter = "${DC}"
region = "${DC}"
data_dir = "/opt/nomad"
bind_addr = "0.0.0.0"

advertise = {
    http = "{{GetPrivateInterfaces | include \"name\" \"wg0\" | attr \"address\"}}"
    rpc = "{{GetPrivateInterfaces | include \"name\" \"wg0\" | attr \"address\"}}"
    serf = "{{GetPrivateInterfaces | include \"name\" \"wg0\" | attr \"address\"}}"
}

acl {
  enabled = true
}

tls {
  http = true
  rpc = true

  ca_file = "/etc/ssl/certs/global.vault.crt"
  cert_file = "/opt/nomad/agent.crt"
  key_file = "/opt/nomad/agent.key"

  verify_server_hostname = true
}
EOF

emit_tee /etc/nomad.d/server.hcl <<EOF
server {
  enabled = true
  bootstrap_expect = 1
  encrypt = "$(cat data/nomad-gossip.key)"
}

consul {
 token = "$consul_root_token"
 ssl = true
}
EOF

emit_tee /etc/nomad.d/client.hcl <<'EOF'
client {
  enabled = true
  reserved = {
    cpu = 500
    memory = 400
    disk = 1024
  }
}
EOF

emit_tee /etc/systemd/system/nomad.service <<'EOF'
[Unit]
Description=Nomad
Documentation=https://www.nomadproject.io/docs
Wants=network-online.target
After=network-online.target
StartLimitBurst=3
StartLimitIntervalSec=10

[Service]
ExecReload=/bin/kill -HUP $MAINPID
ExecStart=/usr/bin/nomad agent -config /etc/nomad.d
KillMode=process
KillSignal=SIGINT
LimitNOFILE=infinity
LimitNPROC=infinity
Restart=on-failure
RestartSec=2
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOF

# }}}
# Bring up services {{{

echo 'mkdir --parents /run/bootstrap'
echo 'chmod 750 /run/bootstrap'
emit_file data/consul.tar /run/bootstrap/consul.tar
echo

cat <<SCRIPT_END
tar -xf /run/bootstrap/consul.tar -C /opt/consul
chown --recursive consul:consul /opt/consul

systemctl enable --now consul
systemctl restart systemd-resolved
systemctl enable --now vault
export VAULT_ADDR=https://127.0.0.1:8200
export VAULT_CACERT=/etc/ssl/certs/global.vault.crt
while [[ ! \$(vault status) == *Sealed*true* ]]; do sleep 1; done
vault operator unseal "$vault_unseal_key"
/etc/cron.monthly/rotate-certificates
systemctl enable --now nomad
rm -rf /run/bootstrap

SCRIPT_END

# }}}
# vim:foldmethod=marker
