#!/usr/bin/env bash
# @describe Cluster management

set -eu

# @cmd Prepare a new cluster
#
# Note that --driver and --age must come *before* the environment name
# and all driver arguments.
#
# @arg    name $ENVIRONMENT        Name of the cluster
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
      AUTHELIA_SESSION_SECRET: $(head -c 32 /dev/urandom | base64)
      AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET: $(head -c 32 /dev/urandom | base64)
      AUTHELIA_STORAGE_ENCRYPTION_KEY: $(head -c 32 /dev/urandom | base64)
...
EOF
	cat >authelia-users.yml <<'EOF'
users:
  authelia:
    disabled: false
    displayname: 'Authelia User'
    # Password is authelia
    password: '$6$rounds=50000$BpLnfgDsc2WD8F2q$Zis.ixdg9s/UOJYrs56b5QEZFiZECu0qZVNsIYxBaNJ7ucIL.nlxVCT5tqh8KHG8X4tlwCFm5r6NTOZZ5qRFN/'
    email: 'ry@cgamesplay.com'
    groups:
      - 'admin'
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
	jsonnet -J "env/${argc_name:?}" -J workloads -y \
		--tla-str "key=${argc_workload:?}" \
		-e "function(key) (import 'main.jsonnet').manifests(key)"
}

# @cmd Render an environment's manifests for a particular workload
# @arg    name![`choose_env`] $ENVIRONMENT  Name of the cluster
# @arg    workload![?`choose_workload`]      Name of workload to render
# @meta require-tools jsonnet,kapp
render() {
	_render_manifest
}

# @cmd Show a diff of manifest changes
# @arg    name![`choose_env`] $ENVIRONMENT  Name of the cluster
# @arg    workload![?`choose_workload`]      Name of workload to consider
# @meta require-tools jsonnet,kapp
diff() {
	export KUBECONFIG="env/${argc_name:?}/kubeconfig.yml"
	manifest=$(_render_manifest)
	kapp deploy -a "${argc_workload:?}" -c --diff-run -f <(echo "$manifest")
}

# @cmd Apply the current manifests to the environment
# @arg    name![`choose_env`] $ENVIRONMENT  Name of the cluster
# @arg    workload![?`choose_workload`]      Name of workload to consider
# @flag   --yes                             Automatically accept kapp apps
# @meta require-tools jsonnet,kapp
apply() {
	export KUBECONFIG="env/${argc_name:?}/kubeconfig.yml"
	manifest=$(_render_manifest)
	kapp deploy -a "${argc_workload:?}" -c ${argc_yes:+--yes} -f <(echo "$manifest")
}

# @cmd Sync all enabled workloads
# @arg     name![`choose_env`] $ENVIRONMENT  Name of the cluster
# @flag -n --dry-run                         Show the changes without applying them
# @flag -y --yes                             Automatically accept kapp apps
sync() {
	workloads=$(jsonnet -J "env/${argc_name:?}" -J workloads -S \
		-e "local C = import 'main.jsonnet'; std.join('\n', std.sort(std.objectFields(C.config.workloads), function(id) C.decls[id].priority))")
	for workload in $workloads; do
		if [ ${argc_dry_run:+1} ]; then
			argc diff "${argc_name:?}" "$workload"
		else
			argc apply ${argc_yes:+--yes} "${argc_name:?}" "$workload"
		fi
	done
}

# @cmd Unseal the cluster
# @arg    name![`choose_env`]  Name of the cluster
unseal() {
	cd "env/${argc_name:?}"
	./driver unseal "${argc_name:?}"
}

# @cmd Replace the cluster's server with a new one
# @flag   --driver-help        Show help for the driver
# @arg    name![`choose_env`]  Name of the cluster
# @arg    args~                Arguments for driver
upgrade() {
	cd "env/${argc_name:?}"
	if [ ${argc_driver_help:+1} ]; then
		exec ./driver upgrade --help
	fi
	./driver upgrade "${argc_name:?}" ${argc_args+"${argc_args[@]}"}
}

# @cmd Destroy the cluster
# @arg    name![`choose_env`]  Name of the cluster
destroy() {
	[ ! -d "env/${argc_name:?}" ] && exit 0
	cd "env/${argc_name:?}"
	./driver destroy "${argc_name:?}"
	cd ../..
	rm -rf "env/${argc_name:?}"
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
