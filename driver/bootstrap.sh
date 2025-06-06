#!/bin/sh
set -eux

apt-get update
apt-get install age

curl -sfL https://get.k3s.io | \
	INSTALL_K3S_CHANNEL=${INSTALL_K3S_CHANNEL:?} \
	INSTALL_K3S_SKIP_START=true \
	K3S_NODE_NAME=main \
	sh -

mkdir -p /etc/rancher/k3s

cat >/etc/rancher/k3s/config.yaml <<-EOF
disable: metrics-server
EOF

if [ -n "$(ip -6 addr show scope global)" ]; then
  cat >>/etc/rancher/k3s/config.yaml <<-EOF
cluster-cidr: 10.42.0.0/16,fd00:cafe:42::/56
service-cidr: 10.43.0.0/16,fd00:cafe:43::/112
flannel-ipv6-masq: true
EOF
fi

mkdir -p /etc/systemd/system/k3s.service.d/
cat >/etc/systemd/system/k3s.service.d/override.conf <<-EOF
[Unit]
After=var-lib-rancher.mount
Requires=var-lib-rancher.mount
EOF

cat >/usr/local/bin/unseal <<-EOF
#!/bin/sh
set -e
cryptsetup luksOpen "${BLOCK_DEVICE:?}" data
echo "Drive opened successfully. Starting k3s..."
systemctl start k3s
EOF
chmod +x /usr/local/bin/unseal

echo "/dev/mapper/data /var/lib/rancher ext4 noauto 0 0" >>/etc/fstab
echo "data ${BLOCK_DEVICE:?} none noauto,headless=true" >>/etc/crypttab

# Set up a local (ephemeral) containerd storage area
mkdir -m 700 /opt/containerd

if [ ${FORMAT_DRIVE:+1} ]; then
	KEY_FILE=/run/disk.key
	set +x
	printf "%s" "${DISK_PASSWORD:?}" > "$KEY_FILE"
	set -x

	cryptsetup luksFormat "$BLOCK_DEVICE" -d "$KEY_FILE"
	cryptsetup luksOpen "$BLOCK_DEVICE" data -d "$KEY_FILE"
	rm "$KEY_FILE"
	mkfs.ext4 /dev/mapper/data
	systemctl daemon-reload
	mkdir /var/lib/rancher
	mount "/var/lib/rancher"

	mkdir -m 700 /var/lib/rancher/k3s
	mkdir -m 700 /var/lib/rancher/k3s/server
	mkdir -m 700 /var/lib/rancher/k3s/server/static
	mkdir -m 700 /var/lib/rancher/k3s/server/static/charts
	mkdir -m 700 /var/lib/rancher/k3s/server/manifests
	mkdir -m 700 /var/lib/rancher/k3s/agent
	ln -s /opt/containerd /var/lib/rancher/k3s/agent/containerd

	# Need to vendor the helm chart to ensure that it doesn't get
	# tampered with.
	# https://isindir.github.io/sops-secrets-operator/index.yaml
	curl -fsSL https://isindir.github.io/sops-secrets-operator/sops-secrets-operator-0.22.0.tgz -o /var/lib/rancher/k3s/server/static/charts/sops-secrets-operator-0.22.0.tgz
	shasum -c <<-EOF
28ebe7da0812a9f6cabc9d655dec2f7bb4ad7af789751afdb998eb0f570d1543  /var/lib/rancher/k3s/server/static/charts/sops-secrets-operator-0.22.0.tgz
EOF

	# Drop it in as an add-on. We also want to pin the digest here
	# since it processes all of our secrets. This hash can be found
	# through: docker pull isindir/sops-secrets-operator:0.16.0
	cat >/var/lib/rancher/k3s/server/manifests/sops-secrets-operator.yaml <<-EOF
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: sops-secrets-operator
  namespace: kube-system
spec:
  chart: https://%{KUBERNETES_API}%/static/charts/sops-secrets-operator-0.22.0.tgz
  targetNamespace: kube-system
  valuesContent: |-
    image:
      repository: isindir/sops-secrets-operator
      tag: 0.16.0@sha256:252fc938071a3087b532f5fe4465aff0967c822d5fd4ba271fbb586c522311a6
    secretsAsFiles:
    - mountPath: /etc/sops-age-key-file
      name: sops-age-key-file
      secretName: sops-age-key-file
    extraEnv:
    - name: SOPS_AGE_KEY_FILE
      value: /etc/sops-age-key-file/key
EOF

	service k3s start

	# Create the age key
	age-keygen -o /run/age.key
	age-keygen -y /run/age.key > /tmp/sops-age-recipient.txt
	kubectl create secret generic -n kube-system sops-age-key-file --from-file=key=/run/age.key
	rm -f /run/age.key

	# Wait for k3s to finish its install procedure.
	while ! kubectl wait --for condition=established --timeout=10s crd/ingressroutes.traefik.io; do
		sleep 1
	done

else
	systemctl daemon-reload
	echo "The server will start normally once unseal is complete." >&2
fi
