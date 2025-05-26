#!/bin/sh

set -eux

BLOCK_DEVICE=/dev/vdb

set +x
DISK_PASSWORD=$(head -c 32 /dev/urandom | base64)
ETCD_PASSWORD=$(head -c 32 /dev/urandom | base64)
printf "%s" "$DISK_PASSWORD" >/run/data.key
set -x

cryptsetup luksFormat "$BLOCK_DEVICE" -d /run/data.key
cryptsetup luksOpen "$BLOCK_DEVICE" data -d /run/data.key
mkfs.ext4 /dev/mapper/data
echo "/dev/mapper/data /var/opt ext4 noauto 0 0" >>/etc/fstab
echo "data $BLOCK_DEVICE none noauto,headless=true" >>/etc/crypttab
systemctl daemon-reload
mount "/var/opt"

mkdir /var/opt/k3s
chmod 700 /var/opt/k3s
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
              secret: "$ETCD_PASSWORD"
      - identity: {}
EOF

mkdir /etc/rancher/k3s/config.yaml.d
cat >/etc/rancher/k3s/config.yaml.d/local.yml <<-EOF
kube-apiserver-arg: encryption-provider-config=/var/opt/k3s/encryption.yml
disable: traefik,metrics-server
EOF

service k3s stop
mkdir -p /etc/systemd/system/k3s.service.d/
cat >/etc/systemd/system/k3s.service.d/override.conf <<-EOF
[Unit]
After=var-opt.mount
Requires=var-opt.mount
EOF

systemctl daemon-reload
k3s server --cluster-reset
rm -rf /var/lib/rancher/k3s/server/db/
service k3s start

cat >/usr/local/bin/unseal <<-EOF
#!/bin/sh
set -e
cryptdisks_start data
systemctl start k3s
EOF
chmod +x /usr/local/bin/unseal

echo "DISK ENCRYPTION PASSWORD: $(cat /run/data.key)"
rm /run/data.key
