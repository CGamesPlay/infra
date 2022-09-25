from .dsl import ScriptIO


def get_script(options):
    script = ScriptIO()
    script.print("set -uexo pipefail")

    script.print_section(
        """
        # Copy existing install to the new volume
        cp /dev/sda1 /dev/sdb
        e2fsck -fp /dev/sdb
        resize2fs /dev/sdb

        # Partition the original disk
        sgdisk /dev/sda -s
        sgdisk /dev/sda -d 3 -n 0:0:+4G -t 0:8200 -c 0:swap -n 0:0:+1M -t 0:8300 -c 0:ephemeral

        # Format partitions
        mkswap /dev/sda3
        mkfs.ext4 /dev/sda4

        # Mount new disk
        mount /dev/sdb /mnt
        for i in dev dev/pts sys tmp run proc; do mount --bind /$i /mnt/$i; done
        mkdir /mnt/media/ephemeral
        chmod 01777 /mnt/media/ephemeral

        chroot /mnt /bin/bash -s <<'EXIT_CHROOT'
        set -uexo pipefail

        # Set up fstab
        cat <<EOF > /etc/fstab
        # /etc/fstab: static file system information.
        #
        # Use 'blkid' to print the universally unique identifier for a
        # device; this may be used with UUID= as a more robust way to
        # name devices that works even if disks are added and removed.
        # See fstab(5).
        #
        # <file system> <mount point>   <type>  <options>       <dump>  <pass>
        UUID=$(lsblk -no UUID /dev/sdb) / ext4 defaults,errors=remount-ro 0 1
        /dev/sda2 /boot/efi vfat defaults 0 2
        /dev/sda3 none swap sw 0 0
        /dev/sda4 /media/ephemeral ext4 defaults,errors=remount-ro 0 2
        EOF

        cat <<EOF >/etc/cloud/cloud.cfg.d/91-private-server.cfg
        # Private Server cloud-config
        # This script disables most per-instance cloud-init modules, since
        # these don't make sense in the context of a persistent root volume.

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

        cat <<'EOF' >/var/lib/cloud/scripts/per-boot/resize-ephemeral-disk.sh
        #!/bin/bash
        set -xueo pipefail
        sgdisk -e -d 4 -N 4 /dev/sda
        partprobe
        resize2fs /dev/sda4
        EOF

        # Update the bootloader
        update-grub
        grub-install /dev/sda

        EXIT_CHROOT
        sync
        """
    )
    return script.getvalue()
