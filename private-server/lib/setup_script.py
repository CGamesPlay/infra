from .dsl import ScriptIO


def get_script(options):
    script = ScriptIO()
    script.print("set -uexo pipefail")

    script.print_section(
        """
        # Copy existing install to the new volume
        e2fsck -fp /dev/sda1
        cp /dev/sda1 /dev/sdb
        tune2fs -U random /dev/sdb
        resize2fs /dev/sdb
        """
    )

    if options.encrypt:
        # Resize the filesystem on the existing install to reuse it
        # later.
        script.print("resize2fs /dev/sda1 3G")

        # The target partition scheme is:
        # EFI system    1 MiB
        # BIOS boot     256 MiB
        # 1st stage     4 GiB
        # Swap          4 GiB
        # Ephemeral     1 GiB (resized on boot)
        partitions = "-d 3 -n 0:0:+4G -t 0:8300 -c 0:stage1 -n 0:0:+4G -t 0:8200 -c 0:swap -n 0:0:+1G -t 0:8300 -c 0:ephemeral"
    else:
        # The target partition scheme is:
        # EFI system    1 MiB
        # BIOS boot     256 MiB
        # Swap          4 GiB
        # Ephemeral     1 GiB (resized on boot)
        partitions = (
            "-d 3 -n 0:0:+4G -t 0:8200 -c 0:swap -n 0:0:+1G -t 0:8300 -c 0:ephemeral"
        )

    script.print_section(
        f"""
        # Partition the original disk
        sgdisk /dev/sda -s
        sgdisk /dev/sda {partitions}
        sleep 2 # Wait for udev to update

        # Format partitions
        mkswap /dev/disk/by-partlabel/swap
        mkfs.ext4 /dev/disk/by-partlabel/ephemeral
        """
    )

    if options.encrypt:
        script.write(get_stage1(options))

    script.print_section(
        """
        # Mount new disk
        mount /dev/sdb /mnt
        for i in dev dev/pts sys tmp run proc; do
            mount --bind /$i /mnt/$i
        done
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
        PARTLABEL=ephemeral /media/ephemeral ext4 defaults,errors=remount-ro 0 2
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
        """
    )

    if not options.encrypt:
        script.print_section(
            """
            # Update the bootloader
            update-grub
            grub-install /dev/sda
            """
        )

    script.print_section(
        """
        EXIT_CHROOT
        sync
        """
    )
    return script.getvalue()


def get_stage1(options):
    script = ScriptIO()
    script.print_section(
        """
        # Mount new disk
        resize2fs /dev/disk/by-partlabel/stage1
        mount /dev/disk/by-partlabel/stage1 /mnt
        for i in dev dev/pts sys tmp run proc; do
            mount --bind /$i /mnt/$i
        done

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
        PARTLABEL=stage1 / ext4 defaults,errors=remount-ro 0 1
        EOF

        cat <<EOF >/etc/cloud/cloud.cfg.d/91-private-server.cfg
        # Private Server stage1 cloud-config
        # Cloud-init is mostly disabled, but some modules still run.
        preserve_hostname: true
        EOF

        systemctl disable cloud-init cloud-config cloud-final
        systemctl disable sshd ssh
        hostnamectl set-hostname stage1

        # Update the bootloader
        sed -ie '/GRUB_CMDLINE_LINUX_DEFAULT/s/="/="systemd.gpt_auto=false /' /etc/default/grub
        update-grub
        grub-install /dev/sda

        echo 'root:password' | chpasswd

        export DEBIAN_FRONTEND=noninteractive
        apt-get update -yq
        apt-get install -yq kexec-tools

        cat <<EOF > /usr/local/bin/ps-kexec
        #!/bin/sh
        mount /dev/sdb /mnt
        kexec -l /mnt/boot/vmlinuz --initrd=/mnt/boot/initrd.img --append="root=/dev/sdb ro consoleblank=0 systemd.show_status=true console=tty1 console=ttyS0"
        systemctl kexec
        EOF
        chmod +x /usr/local/bin/ps-kexec

        cat <<EOF > /etc/systemd/system/ps-kexec.service
        [Unit]
        Description="Stage1 Kexec"

        [Service]
        Type=oneshot
        ExecStart=/usr/local/bin/ps-kexec
        RemainAfterExit=yes

        [Install]
        WantedBy=multi-user.target
        EOF
        systemctl enable ps-kexec

        EXIT_CHROOT

        umount /mnt/dev/pts /mnt/dev /mnt/sys /mnt/tmp /mnt/run /mnt/proc /mnt
        """
    )

    return script.getvalue()
