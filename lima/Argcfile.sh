#!/usr/bin/env bash
# @describe Set up a local cluster with Lima
# @option --cluster=cluster  Name of the Lima VM to use

set -eu

# @cmd Prepare to recreate the cluster from scratch
# @meta require-tools age-keygen,sops
prepare() {
	age-keygen -o development.key 2>/dev/null
	AGE_RECIPIENT=$(age-keygen -y development.key)
	sops --encrypt --age "$AGE_RECIPIENT" --encrypted-suffix Templates --input-type yaml --output-type yaml /dev/stdin > admin-secrets.yml <<EOF
apiVersion: isindir.github.com/v1alpha3
kind: SopsSecret
metadata:
  name: sops-secrets
  namespace: admin
spec:
  # https://github.com/isindir/sops-secrets-operator/blob/147febf336f14bb2546eec020680ce1b2a2e96f1/api/v1alpha3/sopssecret_types.go#L33
  secretTemplates: []
EOF
}

# @cmd Edit a secret with sops
sops-edit() {
	SOPS_AGE_KEY_FILE=$(pwd)/development.key
	export SOPS_AGE_KEY_FILE
	cd "${ARGC_PWD:?}"
	exec sops edit "$@"
}

# @cmd Create the cluster
# @meta require-tools limactl,kubectl,sops,terraform
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

	head -c 32 /dev/urandom | base64 > data.key
	cat data.key | limactl shell "$argc_cluster" sudo sh -c 'tr -d \\n >/run/data.key'
	cat bootstrap.sh | limactl shell "$argc_cluster" sudo sh
	export KUBECONFIG="$HOME/.lima/$argc_cluster/copied-from-guest/kubeconfig.yaml"
	kubectl create namespace terraform

	# Bootstrap the sops secrets file
	kubectl create secret generic -n kube-system sops-age-key-file --from-file=key=development.key

	# Wait for Traefik to be installed
	while ! kubectl -system wait --for condition=established --timeout=10s crd/ingressroutes.traefik.io; do
		sleep 1
	done

	# Apply terraform config
	terraform init
	terraform apply -auto-approve
}

# @cmd Delete the cluster
destroy() {
	if limactl list "${argc_cluster:?}" >/dev/null 2>&1; then
		limactl delete --force "$argc_cluster"
	fi
	if [ -n "$(limactl disk list --json "${argc_cluster:?}" 2>/dev/null)" ]; then
		limactl disk delete "$argc_cluster"
	fi
	rm -f data.key
}

if ! command -v argc >/dev/null; then
	echo "This command requires argc. Install from https://github.com/sigoden/argc" >&2
	exit 100
fi
eval "$(argc --argc-eval "$0" "$@")"
