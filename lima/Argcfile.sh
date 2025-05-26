#!/usr/bin/env bash
# @describe Set up a local cluster with Lima
# @option --cluster=cluster  Name of the Lima VM to use

set -eu

# @cmd Create the cluster
create() {
	if [ -n "$(limactl disk list --json "${argc_cluster:?}" 2>/dev/null)" ]; then
		echo "limactl: disk $argc_cluster already exists" >&2
		exit 1
	fi
	if limactl list "${argc_cluster:?}" >/dev/null 2>&1; then
		echo "limactl: machine $argc_cluster already exists" >&2
		exit 1
	fi

	limactl disk create "$argc_cluster" --format raw --size $(( 5 * 1024 * 1024 * 1024 ))
	limactl create \
		--name="$argc_cluster" \
		--disk=20 \
		--yes \
		template://k3s \
		--set '.additionalDisks += [{"name": "'"$argc_cluster"'", "format": false}]'
	limactl start "$argc_cluster"
	cat bootstrap.sh | limactl shell "$argc_cluster" sudo sh
	export KUBECONFIG="$HOME/.lima/$argc_cluster/copied-from-guest/kubeconfig.yaml"
}

# @cmd Delete the cluster
destroy() {
	if limactl list "${argc_cluster:?}" >/dev/null 2>&1; then
		limactl delete --force "$argc_cluster"
	fi
	if [ -n "$(limactl disk list --json "${argc_cluster:?}" 2>/dev/null)" ]; then
		limactl disk delete "$argc_cluster"
	fi
}

if ! command -v argc >/dev/null; then
	echo "This command requires argc. Install from https://github.com/sigoden/argc" >&2
	exit 100
fi
eval "$(argc --argc-eval "$0" "$@")"
