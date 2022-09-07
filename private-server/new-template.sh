#!/bin/sh
set -ue

# Name of the snapshot/volume to create. These may be freely renamed, and
# the snapshots are not tied to a particular volume.
name="$1"
# Name or ID of the SSH key to use for initial setup, as shown by hcloud
# ssh-key list.
ssh_key="$2"
# Which machine image to use for the bootable volume.
image="ubuntu-22.04"
# Type of server to perform the installation on. Note that the snapshot
# created from this server type will have a disk size equal to the server
# type's disk, and the snapshot will never boot on a server type with a
# smaller disk. I recommend leaving this as CX11, with a 20 GB disk.
machine_type="cx11"
# Location to place the snapshot and volume into.
location="nbg1"
# The size of the cloud volume to create, in GB. This can be increaased
# using the Hetzner console later, but can never be reduced.
initial_size="10"

if [ -z "${HCLOUD_TOKEN:=}" ]; then
    echo "HCLOUD_TOKEN must be set" >&2
    exit 1
fi

output=$(hcloud server create --name "$name" --image "$image" --type "$machine_type" --location "$location" --start-after-create=false --ssh-key="$ssh_key")
ipv4=$(echo "$output" | grep IPv4 | cut -d: -f 2 | xargs)
echo IP "$ipv4"
hcloud volume create --name "$name" --size "$initial_size" --server "$name"
output=$(hcloud server enable-rescue "$name" --ssh-key="$ssh_key")
hcloud server poweron "$name"
echo 'Wait for SSH'
timeout 120 sh -c 'until nc -z $0 22; do sleep 1; done' $ipv4
sleep 5
cat <<'END_SCRIPT' | sed -e "s/%HCLOUD_TOKEN%/$(echo $HCLOUD_TOKEN | sed 's/\//\\\//g')/g" | ssh -l root -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $ipv4 -- 'bash -s'
set -uexo pipefail

# Copy existing install to the new volume
cp /dev/sda1 /dev/sdb
e2fsck -fp /dev/sdb
resize2fs /dev/sdb

# Partition original disk
sgdisk -s /dev/sda
sgdisk -d 3 -n 3:0:+4G -t 0:8200 -n 4:0:+4G -t 0:8300 /dev/sda
mkswap /dev/sda3
mkfs.ext4 /dev/sda4

# Mount new disk
mount /dev/sdb /mnt
for i in dev dev/pts sys tmp run proc; do mount --bind /$i /mnt/$i; done
mkdir /mnt/media/ephemeral

# Set up fstab
cat <<EOF > /mnt/etc/fstab
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
UUID=$(lsblk -no UUID /dev/sdb) / ext4 defaults,errors=remount-ro 0 1
UUID=$(lsblk -no UUID /dev/sda2) /boot/efi vfat defaults 0 2
UUID=$(lsblk -no UUID /dev/sda3) none swap sw 0 0
UUID=$(lsblk -no UUID /dev/sda4) /media/ephemeral ext4 defaults,errors=remount-ro 0 2
EOF

cat <<EOF >/mnt/etc/cloud/cloud.cfg.d/91-private-server.cfg
# Private Server cloud-config
# This script disables most per-instance cloud-init modules, since these
# don't make sense in the context of a persistent root volume.

# The modules that run in the 'init' stage
cloud_init_modules:
 - migrator
 - seed_random
 - bootcmd
 - [ write-files, once ]
 - [ growpart, always ]
 - [ resizefs, always ]
 - [ disk_setup, once ]
 - [ mounts, once ]
 - set_hostname
 - update_hostname
 - [ update_etc_hosts, once-per-instance ]
 - [ ca-certs, once ]
 - [ rsyslog, once ]
 - [ users-groups, once ]
 - [ ssh, once ]

# The modules that run in the 'config' stage
cloud_config_modules:
# Emit the cloud config ready event
# this can be used by upstart jobs for 'start on cloud-config'.
 - emit_upstart
 - [ snap, once ]
 - [ ssh-import-id, once ]
 - keyboard
 - [ locale, once ]
 - [ set-passwords, once ]
 - [ grub-dpkg, once ]
 - [ apt-pipelining, once ]
 - [ apt-configure, once ]
 - [ ubuntu-advantage, once ]
 - [ ntp, once ]
 - [ timezone, once ]
 - disable-ec2-metadata
 - [ runcmd, once ]
 - [ byobu, once ]

# The modules that run in the 'final' stage
cloud_final_modules:
 - [ package-update-upgrade-install, once ]
 - [ fan, once ]
 - [ landscape, once ]
 - [ lxd, once ]
 - [ ubuntu-drivers, once ]
 - [ write-files-deferred, once ]
 - [ puppet, once ]
 - chef
 - [ mcollective, once ]
 - [ salt-minion, once ]
 - reset_rmc
 - refresh_rmc_and_interface
 - [ rightscale_userdata, once ]
 - scripts-vendor
 - scripts-per-once
 - scripts-per-boot
 - [ scripts-per-instance, once ]
 - [ scripts-user, once ]
 - [ ssh-authkey-fingerprints, once ]
 - [ keys-to-console, once ]
 - [ install-hotplug, once ]
 - [ phone-home, once ]
 - final-message
 - power-state-change
EOF

cat <<'EOF' >/mnt/usr/local/sbin/hcloud-self-destruct
#!/bin/sh
# Immediately destroy this server
set -e
if [ "$(systemctl show --property=Job poweroff.target)" = "Job=" ]; then
    echo "Aborting self destruct because system is not powering off" >&2
    exit 0
fi

server=$(cat /var/run/cloud-init/.instance-id)
# Just allow the system to cool down
sleep 5
sync
hcloud server delete $server
EOF
chmod +x /mnt/usr/local/sbin/hcloud-self-destruct

cat <<'EOF' >/mnt/etc/systemd/system/self-destruct.service
[Unit]
Description=self destruct on poweroff

# We want to stop this service pretty late in the shutdown process, but
# before the network goes down. By setting Before=network.target, our self
# destruct will only happen after everything which is After=network.target.
Before=network.target user.slice machine.slice
# But the self destruct requires the network to actually be active.
After=systemd-networkd.service nss-lookup.target

[Service]
EnvironmentFile=-/etc/self-destruct.env
ExecStop=/usr/local/sbin/hcloud-self-destruct --force
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

echo 'HCLOUD_TOKEN=%HCLOUD_TOKEN%' >> /mnt/etc/self-destruct.env

chroot /mnt /bin/bash -s <<EXIT_CHROOT
set -uexo pipefail
update-grub
grub-install /dev/sda

apt-get update
apt-get install -y hcloud-cli
systemctl enable self-destruct.service
EXIT_CHROOT
END_SCRIPT

hcloud server shutdown "$name"
create_image_output="$(hcloud server create-image "$name" --type snapshot --description="$image with external root device")"
image_id="$(echo "$create_image_output" | awk '{ print $2 }')"
hcloud server delete "$name"

echo
echo "=================================================================="
echo "Volume and snapshot completed successfully."
echo "Snapshot:"
hcloud image describe "$image_id"
echo
echo "Volume:"
hcloud volume describe "$name" | egrep '^(ID|Name|Size)'
echo
echo "To boot this volume, use a command like this:"
echo
echo "  hcloud server create --location $location --volume $name --image $image_id --name $name --type $machine_type"
