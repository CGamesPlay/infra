#!/usr/bin/env bash
# @describe Cluster management

set -eu

# @cmd Prepare a new cluster
#
# Note that --driver and --age must come *before* the environment name
# and all driver arguments.
#
# @arg    name                     Name of the cluster
# @arg    args~                    Arguments for driver
# @option --age $AGE_PUBLIC_KEY    Admin's age public key to use
# @option --k3s-channel=stable     K3s channel to use
# @option --driver![lima|hetzner]  Type of cluster to create
# @flag   --driver-help            Show help for the driver
# @meta require-tools sops,terraform,kubectl
init() {
	if [ ${argc_driver_help+1} ]; then
		exec "./driver/${argc_driver:?}" init --help
	fi
	"./driver/${argc_driver:?}" init --validate-args-only "${argc_name:?}" ${argc_args+"${argc_args[@]}"}
	mkdir "env/${argc_name:?}"
	cd "env/${argc_name:?}"
	ln -s "../../driver/${argc_driver:?}" driver
	DISK_PASSWORD=$(head -c 32 /dev/urandom | base64)
	export DISK_PASSWORD
	export INSTALL_K3S_CHANNEL="${argc_k3s_channel:?}"

	./driver init "${argc_name:?}" ${argc_args+"${argc_args[@]}"}

	CLUSTER_AGE_PUBLIC_KEY=$(cat sops-age-recipient.txt)
	age_keys="${argc_age:-}${argc_age:+,}$CLUSTER_AGE_PUBLIC_KEY"
	sops --encrypt --age "$age_keys" --encrypted-suffix Templates --input-type yaml --output-type yaml /dev/stdin > secrets.yml <<EOF
---
apiVersion: isindir.github.com/v1alpha3
kind: SopsSecret
metadata:
  name: sops-secrets
  namespace: admin
spec:
  # https://github.com/isindir/sops-secrets-operator/blob/147febf336f14bb2546eec020680ce1b2a2e96f1/api/v1alpha3/sopssecret_types.go#L33
  secretTemplates:
  - name: authelia
    stringData:
      configuration.secret.yml: |
        session:
          secret: $(openssl rand -base64 32)
        identity_validation:
          reset_password:
            jwt_secret: $(openssl rand -base64 32)
        storage:
          encryption_key: $(openssl rand -base64 32)
        identity_providers:
          oidc:
            hmac_secret: $(openssl rand -base64 32)
            jwks:
              - key: |
$(openssl genrsa 2048 | sed -e "s/^/                  /")
EOF
	cp ../../workloads/config.template.libsonnet config.libsonnet

	export KUBECONFIG=kubeconfig.yml

	cat <<-EOF
	########################################
	#       DISK ENCRYPTION PASSWORD       #
	########################################

	$DISK_PASSWORD

	Warning: this password will not be stored automatically. Copy it
	to a safe place.
	EOF
}

_render_manifest() {
	jsonnet -J "env/${argc_environment:?}" -J workloads -y \
		--tla-str "key=${argc_workload:?}" \
		-e "function(key) (import 'main.jsonnet').manifests(key)"
}

# @cmd Render an environment's manifests for a particular workload
# @arg    workload![?`choose_workload`]      Name of workload to render
# @option -e --environment![`choose_env`] $CLUSTER_ENVIRONMENT  Environment to work on
# @meta require-tools jsonnet,kapp
render() {
	_render_manifest
}

# @cmd Show a diff of manifest changes
# @arg    workload![?`choose_workload`]      Name of workload to consider
# @option -e --environment![`choose_env`] $CLUSTER_ENVIRONMENT  Environment to work on
# @meta require-tools jsonnet,kapp
diff() {
	export KUBECONFIG="env/${argc_environment:?}/kubeconfig.yml"
	manifest=$(_render_manifest)
	kapp deploy -a "${argc_workload:?}" -c --diff-run -f <(echo "$manifest")
}

# @cmd Apply the current manifests to the environment
# @arg    workload![?`choose_workload`]      Name of workload to consider
# @option -e --environment![`choose_env`] $CLUSTER_ENVIRONMENT  Environment to work on
# @flag   --yes                              Automatically accept kapp apps
# @meta require-tools jsonnet,kapp
apply() {
	export KUBECONFIG="env/${argc_environment:?}/kubeconfig.yml"
	manifest=$(_render_manifest)
	kapp deploy -a "${argc_workload:?}" -c ${argc_yes:+--yes} -f <(echo "$manifest")
}

# @cmd Sync all enabled workloads
# @option -e --environment![`choose_env`] $CLUSTER_ENVIRONMENT  Environment to work on
# @flag -n --dry-run                         Show the changes without applying them
# @flag -y --yes                             Automatically accept kapp apps
sync() {
	workloads=$(jsonnet -J "env/${argc_environment:?}" -J workloads -S \
		-e "local C = import 'main.jsonnet'; std.join('\n', std.sort(std.objectFields(C.config.workloads), function(id) C.decls[id].priority))")
	for workload in $workloads; do
		echo "*** $workload ***"
		if [ ${argc_dry_run:+1} ]; then
			argc diff -e "${argc_environment:?}" "$workload"
		else
			argc apply ${argc_yes:+--yes} -e "${argc_environment:?}" "$workload"
		fi
	done
}

# @cmd Unseal the cluster
# @option -e --environment![`choose_env`] $CLUSTER_ENVIRONMENT  Environment to work on
unseal() {
	cd "env/${argc_environment:?}"
	./driver unseal "${argc_environment:?}"
}

# @cmd Replace the cluster's server with a new one
# @flag   --driver-help        Show help for the driver
# @option --k3s-channel=stable     K3s channel to use
# @option -e --environment![`choose_env`] $CLUSTER_ENVIRONMENT  Environment to work on
# @arg    args~                Arguments for driver
upgrade() {
	cd "env/${argc_environment:?}"
	if [ ${argc_driver_help:+1} ]; then
		exec ./driver upgrade --help
	fi
	export INSTALL_K3S_CHANNEL="${argc_k3s_channel:?}"
	./driver upgrade "${argc_environment:?}" ${argc_args+"${argc_args[@]}"}
}

# @cmd Destroy the cluster
# @option -e --environment![`choose_env`] $CLUSTER_ENVIRONMENT  Environment to work on
destroy() {
	[ ! -d "env/${argc_environment:?}" ] && exit 0
	cd "env/${argc_environment:?}"
	./driver destroy "${argc_environment:?}"
	cd ../..
	rm -rf "env/${argc_environment:?}"
}

# @cmd Download external dependencies
#
# Required for each local checkout.
prepare() {
	if [ ! -f workloads/cert-manager/cert-manager.yml ]; then
		curl -fsSL https://github.com/cert-manager/cert-manager/releases/download/v1.17.2/cert-manager.yaml -o workloads/cert-manager/cert-manager.yml
		if ! shasum -c workloads/cert-manager/cert-manager.yml.sum; then
			rm workloads/cert-manager/cert-manager.yml
			exit 1
		fi
	fi
}

# @cmd Activate the named environment
#
# Use this to set defaults for various environment variables.
# @arg     name![`choose_env`] Name of the environment to activate
activate() {
	echo "echo 'Activating environment ${argc_name:?}'"
	echo "export CLUSTER_ENVIRONMENT=${argc_name:?}"
	echo "export KUBECONFIG=$(pwd)/env/${argc_name:?}/kubeconfig.yml"
}

choose_env() {
	for dir in env/*; do
		echo "${dir#env/}"
	done
}

choose_workload() {
	jsonnet -J workloads -S -e "std.join('\n', std.objectFields((import 'main.jsonnet').decls))"
}

if ! command -v argc >/dev/null; then
	echo "This command requires argc. Install from https://github.com/sigoden/argc" >&2
	exit 100
fi
eval "$(argc --argc-eval "$0" "$@")"
# vim:set ts=4
