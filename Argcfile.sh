#!/usr/bin/env bash
# @describe Example Argcfile
# For more information about argc, see https://github.com/sigoden/argc

set -eu

ansible_variables=(
  -e DC=nbg1 -e wireguard_ip=172.30.0.1 -e traefik_domain="${BASE_DOMAIN:?}"
)

# @cmd Ensure that all cloud resources are up to date
#
# Example: preview infrastructure changes
#   argc infra plan
#
# Example: apply infrastructure changes
#   argc infra apply
#
# Example: see terraform usage
#   argc infra -- --help
#
# @arg    args+                          Arguments to terraform
# @option -e --environment=prod-control  Environment to use
infra() {
	export TF_WORKSPACE=${argc_environment:?}
	exec terraform -chdir=terraform "${argc_args[0]:?}" -var-file="${TF_WORKSPACE}.tfvars" "${argc_args[@]:1}"
}

# @cmd Get the IP address of master.node.consul
# @option -e --environment=prod-control  Environment to use
master-ip() {
	export TF_WORKSPACE=${argc_environment:?}
	terraform -chdir=terraform output -raw master_ip
	echo
}

# @cmd Sync all configuration files on the master server
#
# Example: preview changes
#   argc ansible -CD
#
# Example: apply changes
#   argc ansible
#
# Example: see ansible usage
#   argc ansible -- --help
# @arg    args*  Arguments to ansible
ansible() {
	ANSIBLE_CONFIG=ansible/ansible.cfg exec ansible-playbook -u ubuntu -i master.node.consul, "${ansible_variables[@]}" ansible/site.yml ${argc_args+"${argc_args[@]}"}
}

# @cmd Verify that all services are running
#
# Example: see ansible usage
#   argc ansible -- --help
# @arg    args*  Arguments to ansible
verify() {
	exec ansible-playbook -u ubuntu -i master.node.consul, "${ansible_variables[@]}" ansible/playbooks/verify.yml ${argc_args+"${argc_args[@]}"}
}

# @cmd Print environment variables to use services
env() {
	if ! ping -c 1 master.node.consul >/dev/null 2>&1; then
		echo "This script requires that WireGuard is connected and DNS is configured." >&2
		exit 1
	fi
	export VAULT_ADDR=https://vault.service.consul:8200/
	VAULT_TOKEN=$(ssh master.node.consul -- sudo cat /root/.vault-token)
	export VAULT_TOKEN
	echo "export VAULT_ADDR=$VAULT_ADDR"
	echo "export VAULT_TOKEN=$VAULT_TOKEN"
	cat <<-EOF
	export CONSUL_HTTP_ADDR=consul.service.consul:8500
	export CONSUL_HTTP_TOKEN=$(vault read -field=token kv/cluster/consul)
	export NOMAD_ADDR=https://nomad.service.consul:4646/
	export NOMAD_TOKEN=$(vault read -field=token kv/cluster/nomad)
	EOF
}

# @cmd Ensure that all nomad jobs are up to date
#
# Example: preview infrastructure changes
#   argc nomad plan
#
# Example: apply infrastructure changes
#   argc nomad apply
#
# Example: see terraform usage
#   argc nomad -- --help
#
# @arg    subcommand  Terraform subcommand
# @arg    args~       Additional arguments to terraform
nomad() {
	exec terraform -chdir=nomad "${argc_subcommand:-}" ${argc_args+"${argc_args[@]}"}
}


# @cmd Add Consul DNS to system settings
setup-dns() {
	exec sudo scutil <<-EOF
	d.init
	d.add ServerAddresses * 172.30.0.1
	d.add SupplementalMatchDomains * consul
	set State:/Network/Service/Consul/DNS
	EOF
}

# @cmd Complete integration test in staging environment
integration-test() {
	argc terraform -e test-control apply -- -auto-approve
	# Give some time for ssh to come up. Doesn't slow us down because
	# cloud-init takes time to finish anyways.
	sleep 10
	ANSIBLE_HOST_KEY_CHECKING=False argc ansible -e test-control
}

if ! command -v argc >/dev/null; then
	echo "This command requires argc. Install from https://github.com/sigoden/argc" >&2
	exit 100
fi
eval "$(argc --argc-eval "$0" "$@")"
