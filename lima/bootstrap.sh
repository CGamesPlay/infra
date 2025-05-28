#!/bin/sh

set -eux

BLOCK_DEVICE=/dev/vdb
KEY_FILE=/run/data.key

cryptsetup luksFormat "$BLOCK_DEVICE" -d "$KEY_FILE"
cryptsetup luksOpen "$BLOCK_DEVICE" data -d "$KEY_FILE"
rm "$KEY_FILE"
mkfs.ext4 /dev/mapper/data
echo "/dev/mapper/data /var/opt ext4 noauto 0 0" >>/etc/fstab
echo "data $BLOCK_DEVICE none noauto,headless=true" >>/etc/crypttab
systemctl daemon-reload
mount "/var/opt"

mkdir /var/opt/k3s /var/opt/pvc
chmod 700 /var/opt/k3s /var/opt/pvc
cat >/var/opt/k3s/encryption.yml <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aesgcm:
          keys:
            - name: key1
              secret: "$(head -c 32 /dev/urandom | base64)"
      - identity: {}
EOF

mkdir /etc/rancher/k3s/config.yaml.d
cat >/etc/rancher/k3s/config.yaml.d/local.yml <<-EOF
kube-apiserver-arg: encryption-provider-config=/var/opt/k3s/encryption.yml
disable: traefik,metrics-server,local-storage
EOF

sed 's@/var/lib/rancher/k3s/storage@/var/opt/pvc@g' /var/lib/rancher/k3s/server/manifests/local-storage.yaml > /var/lib/rancher/k3s/server/manifests/local-local-storage.yaml

# Need to vendor the helm chart to ensure that it doesn't get tampered
# with. https://isindir.github.io/sops-secrets-operator/index.yaml
curl -fsSL https://isindir.github.io/sops-secrets-operator/sops-secrets-operator-0.22.0.tgz -o /var/lib/rancher/k3s/server/static/charts/sops-secrets-operator-0.22.0.tgz
shasum -c <<-EOF
28ebe7da0812a9f6cabc9d655dec2f7bb4ad7af789751afdb998eb0f570d1543  /var/lib/rancher/k3s/server/static/charts/sops-secrets-operator-0.22.0.tgz
EOF

# Drop it in as an add-on. We also want to pin the image name here since
# it processes all of our secrets. This hash can be found through:
# docker pull isindir/sops-secrets-operator:0.16.0
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

service k3s stop
mkdir -p /etc/systemd/system/k3s.service.d/
cat >/etc/systemd/system/k3s.service.d/override.conf <<-EOF
[Unit]
After=var-opt.mount
Requires=var-opt.mount
EOF

cat >/usr/local/bin/unseal <<-EOF
#!/bin/sh
set -e
cryptdisks_start data
systemctl start k3s
EOF
chmod +x /usr/local/bin/unseal

systemctl daemon-reload
k3s server --cluster-reset
rm -rf /var/lib/rancher/k3s/server/db/
service k3s start
