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
# @flag   --age-generate-key       Make a new age key to use
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
	if [[ ${argc_age_generate_key+1} ]]; then
		age-keygen -o age.key
		age_keys="${age_keys},$(age-keygen -y age.key)"
	fi
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
        # notifier:
        #   smtp:
        #     password: smtp-password
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
# @flag   --no-wait                          Don't wait for services to be ready
# @meta require-tools jsonnet,kapp
apply() {
	export KUBECONFIG="env/${argc_environment:?}/kubeconfig.yml"
	manifest=$(_render_manifest)
	kapp deploy -a "${argc_workload:?}" -c ${argc_yes:+--yes} ${argc_no_wait+--wait=false} -f <(echo "$manifest")
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
# @option -e --environment![`choose_env`] Environment to work on
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

# @cmd List all pod container images as JSON
# @option -e --environment![`choose_env`] $CLUSTER_ENVIRONMENT  Environment to work on
# @option -o --output                     Output file path (defaults to stdout)
# @meta require-tools kubectl,jq
list-images() {
	export KUBECONFIG="env/${argc_environment:?}/kubeconfig.yml"

	result=$(kubectl get pods -A -o json | jq '
[.items[] |
  . as $pod |
  (
    ((.status.containerStatuses // []) + (.status.initContainerStatuses // []))
    | map({(.name): .imageID})
    | add // {}
  ) as $imageIdMap |
  ((.spec.containers // []) + (.spec.initContainers // [])) |
  .[] |
  {
    namespace: $pod.metadata.namespace,
    pod: $pod.metadata.name,
    container: .name,
    image: (.image | split("@")[0] | split(":")[0]),
    tag: (.image | split("@")[0] | if contains(":") then split(":")[1] else "latest" end),
    sha: (($imageIdMap[.name] // "") |
          if . == "" then null
          elif contains("sha256:") then (split("sha256:")[1] | split("@")[0])
          else . end)
  }
]')

	if [ "${argc_output:-}" ]; then
		echo "$result" > "${argc_output}"
	else
		echo "$result"
	fi
}

# Check if a tag looks like a semantic version
_is_semver() {
	local tag="$1"
	# Match patterns like: 1.2.3, v1.2.3, 1.2.3-alpine, v1.2.3-rc1, etc.
	[[ "$tag" =~ ^v?[0-9]+\.[0-9]+(\.[0-9]+)?(-[a-zA-Z0-9._-]+)?$ ]]
}

# Get the highest semver tag from a list of tags
# Input: newline-separated list of tags on stdin
# Output: the highest semver tag
_get_latest_semver() {
	local current_tag="$1"
	local v_prefix=""
	local current_suffix=""

	# Extract v prefix and suffix from current tag
	# e.g., "v1.2.3-alpine" -> v_prefix="v", current_suffix="-alpine"
	# e.g., "1.2.3" -> v_prefix="", current_suffix=""
	if [[ "$current_tag" =~ ^(v)?([0-9]+\.[0-9]+(\.[0-9]+)?)(-.+)?$ ]]; then
		v_prefix="${BASH_REMATCH[1]:-}"
		current_suffix="${BASH_REMATCH[4]:-}"
	fi

	# Filter to semver tags with matching v-prefix and suffix, sort, get highest
	grep -E "^${v_prefix}[0-9]+\.[0-9]+(\.[0-9]+)?${current_suffix}$" 2>/dev/null \
		| sort -V \
		| tail -n1
}

# Compare running digest with registry digest
# Returns 0 if digests match, 1 if different
_compare_digests() {
	local image="$1"
	local tag="$2"
	local running_sha="$3"

	# Get current digest from registry (use linux/amd64 for consistency with k8s)
	local registry_sha
	registry_sha=$(skopeo inspect --no-tags --override-os linux --override-arch amd64 \
		"docker://${image}:${tag}" 2>/dev/null \
		| jq -r '.Digest // empty' \
		| sed 's/sha256://')

	if [ -z "$registry_sha" ]; then
		return 2  # Could not fetch
	fi

	# Compare first 64 chars (full sha256)
	if [ "${running_sha:0:64}" = "${registry_sha:0:64}" ]; then
		return 0  # Match
	else
		return 1  # Different
	fi
}

# @cmd Check for outdated container images
# @option -e --environment![`choose_env`] $CLUSTER_ENVIRONMENT  Environment to work on
# @option -f --file                        JSON file from list-images (optional, runs list-images if not provided)
# @meta require-tools kubectl,jq,skopeo
outdated-images() {
	export KUBECONFIG="env/${argc_environment:?}/kubeconfig.yml"

	# Get image data (from file or live)
	local images
	if [ "${argc_file:-}" ]; then
		images=$(cat "$argc_file")
	else
		images=$(list-images)
	fi

	# Build version lookup as JSON object (keyed by "image|tag")
	local version_lookup="{}"

	# Get unique image:tag:sha combinations
	local unique_entries
	unique_entries=$(echo "$images" | jq -c '[.[] | {image, tag, sha}] | unique | .[]')

	while IFS= read -r entry; do
		[ -z "$entry" ] && continue

		local image tag sha latest status
		image=$(echo "$entry" | jq -r '.image')
		tag=$(echo "$entry" | jq -r '.tag')
		sha=$(echo "$entry" | jq -r '.sha // empty')

		if _is_semver "$tag"; then
			# For semver tags, find latest semver
			local all_tags
			all_tags=$(skopeo list-tags "docker://${image}" 2>/dev/null | jq -r '.Tags[]?' 2>/dev/null)

			if [ -z "$all_tags" ]; then
				latest=""
				status="error"
			else
				latest=$(echo "$all_tags" | _get_latest_semver "$tag")

				if [ -z "$latest" ]; then
					latest=""
					status="error"
				elif [ "$tag" = "$latest" ]; then
					status="current"
				else
					status="outdated"
				fi
			fi
		else
			# For non-semver tags, compare digests
			latest=""

			if [ -z "$sha" ]; then
				status="error"
			elif _compare_digests "$image" "$tag" "$sha"; then
				status="current"
			else
				case $? in
					1) status="outdated" ;;
					2) status="error" ;;
				esac
			fi
		fi

		# Add to lookup object
		local key="${image}|${tag}"
		version_lookup=$(echo "$version_lookup" | jq -c \
			--arg k "$key" \
			--arg l "$latest" \
			--arg s "$status" \
			'.[$k] = {latest: (if $l == "" then null else $l end), status: $s}')
	done <<< "$unique_entries"

	# Augment original JSON with version info
	echo "$images" | jq --argjson lookup "$version_lookup" '
		[.[] | . as $entry |
			($entry.image + "|" + $entry.tag) as $key |
			$lookup[$key] as $info |
			$entry + ($info // {latest: null, status: "error"})
		]'
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
