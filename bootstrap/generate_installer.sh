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
    echo "tee $@ <<'EOF'"
    cat
    echo "EOF"
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
echo 'instance_id=$(ec2metadata --instance-id)'
echo

# }}}
# Installing software {{{

ARCH="arm64"
NOMAD_VERSION="1.0.4"
VAULT_VERSION="1.7.1"
CONSUL_VERSION="1.9.5"


cat <<EOF
wget -nv https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_${ARCH}.zip
unzip vault_${VAULT_VERSION}_linux_${ARCH}.zip
rm vault_${VAULT_VERSION}_linux_${ARCH}.zip
mv vault /usr/local/bin/vault
setcap cap_ipc_lock=+ep /usr/local/bin/vault
useradd --system --home /etc/vault.d --shell /usr/sbin/nologin vault

wget -nv https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_${ARCH}.zip
unzip consul_${CONSUL_VERSION}_linux_${ARCH}.zip
rm consul_${CONSUL_VERSION}_linux_${ARCH}.zip
mv consul /usr/local/bin/consul
useradd --system --home /etc/consul.d --shell /usr/sbin/nologin consul

wget -nv https://releases.hashicorp.com/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_linux_${ARCH}.zip
unzip nomad_${NOMAD_VERSION}_linux_${ARCH}.zip
rm nomad_${NOMAD_VERSION}_linux_${ARCH}.zip
mv nomad /usr/local/bin/nomad

EOF

# }}}
# Consul {{{

cat <<'SCRIPT_END'
mkdir --parents /opt/consul /etc/consul.d
chown --recursive consul:consul /opt/consul /etc/consul.d
chmod 750 /etc/consul.d

SCRIPT_END

echo 'echo node_name = \"server-$instance_id\" > /etc/consul.d/consul.hcl'
emit_tee -a /etc/consul.d/consul.hcl <<EOF
datacenter = "${DC}"
data_dir = "/opt/consul"

acl = {
  enabled = true
  default_policy = "deny"
  enable_token_persistence = true
}
EOF

emit_tee /etc/consul.d/server.hcl <<'EOF'
server = true
bootstrap_expect = 1
ui_config {
  enabled = true
}
bind_addr = "{{GetPrivateInterfaces | include \"network\" \"172.31.0.0/16\" | attr \"address\"}}"
EOF

emit_tee /etc/consul.d/client.hcl <<'EOF'
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
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/
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

cat <<'SCRIPT_END'
mkdir --parents /etc/vault.d
mkdir --parents /opt/vault

SCRIPT_END

emit_tee /etc/vault.d/vault.hcl <<EOF
ui = true

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = true
}

storage "consul" {
  address = "127.0.0.1:8500"
  path = "vault/"
  token = "$vault_consul_token"
}
EOF

emit_tee /etc/systemd/system/vault.service <<'EOF'
[Unit]
Description="HashiCorp Vault - A tool for managing secrets"
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
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
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
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
chown --recursive vault:vault /etc/vault.d
chown --recursive vault:vault /opt/vault
chmod 770 /opt/vault
chmod 640 /etc/vault.d/vault.hcl
export VAULT_ADDR=http://127.0.0.1:8200
sed -i '/^VAULT_ADDR=/d' /etc/environment
echo VAULT_ADDR=$VAULT_ADDR >> /etc/environment

SCRIPT_END

# }}}
# Nomad {{{

cat <<'SCRIPT_END'
mkdir --parents /opt/nomad
mkdir --parents /etc/nomad.d
chmod 700 /etc/nomad.d

SCRIPT_END

echo 'echo name = \"$instance_id\" > /etc/nomad.d/nomad.hcl'
emit_tee -a /etc/nomad.d/nomad.hcl <<EOF
datacenter = "${DC}"
data_dir = "/opt/nomad"
EOF

emit_tee /etc/nomad.d/server.hcl <<EOF
server {
  enabled = true
  bootstrap_expect = 1
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
ExecStart=/usr/local/bin/nomad agent -config /etc/nomad.d
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
systemctl enable --now consul; sleep 10
systemctl restart systemd-resolved
systemctl enable --now vault; sleep 5
vault operator unseal "$vault_unseal_key"
systemctl enable --now nomad
rm -rf /run/bootstrap

SCRIPT_END

# }}}
# vim:foldmethod=marker
