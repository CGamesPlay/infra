import pathlib
import base64

from .dsl import ScriptIO


def get_script(options):
    script = ScriptIO()
    script.print("set -uexo pipefail")

    root_device = "/dev/mapper/sdb_crypt" if options.encrypt else "/dev/sdb"
    if options.keyfile:
        keyfile = pathlib.Path(options.keyfile).read_bytes()
        keyfile_b64 = base64.b64encode(keyfile).decode("utf-8")

    if options.encrypt:
        script.print_section(
            f"""
            # Set up the encrypted volume
            echo "{keyfile_b64}" | base64 -d > /run/keyfile
            chmod 0600 /run/keyfile
            cryptsetup luksFormat --type luks2 /dev/sdb /run/keyfile
            cryptsetup open --key-file=/run/keyfile /dev/sdb sdb_crypt
            """
        )

    script.print_section(
        f"""
        # Copy existing install to the new volume
        e2fsck -fp /dev/sda1
        cp /dev/sda1 {root_device}
        tune2fs -U random {root_device}
        resize2fs {root_device}
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
        partitions = "-d 3 -n 0:0:+4G -t 0:8300 -c 0:stage1 -n 0:0:+4G -t 0:8309 -c 0:swap -n 0:0:+1G -t 0:8309 -c 0:ephemeral"
        fstab = [
            "/dev/mapper/ephemeral /media/ephemeral ext4 defaults,errors=remount-ro 0 2",
            "/dev/mapper/swap none swap",
        ]
    else:
        # The target partition scheme is:
        # EFI system    1 MiB
        # BIOS boot     256 MiB
        # Swap          4 GiB
        # Ephemeral     1 GiB (resized on boot)
        partitions = (
            "-d 3 -n 0:0:+4G -t 0:8200 -c 0:swap -n 0:0:+1G -t 0:8300 -c 0:ephemeral"
        )
        fstab = [
            "PARTLABEL=ephemeral /media/ephemeral ext4 defaults,errors=remount-ro 0 2"
        ]

    script.print_section(
        f"""
        # Partition the original disk
        sgdisk /dev/sda -s
        sgdisk /dev/sda {partitions}
        sleep 2 # Wait for udev to update
        """
    )

    if not options.encrypt:
        script.print_section(
            """
            # Format partitions
            mkswap /dev/disk/by-partlabel/swap
            mkfs.ext4 /dev/disk/by-partlabel/ephemeral
            """
        )

    if options.encrypt:
        script.write(get_stage1(options))

    script.print_section(
        f"""
        # Mount new disk
        mount {root_device} /mnt
        for i in dev sys tmp run proc; do
            mount --rbind /$i /mnt/$i
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
        UUID=$(lsblk -no UUID {root_device}) / ext4 defaults,errors=remount-ro 0 1
        EOF
        """
    )

    for line in fstab:
        script.print(f"echo '{line}' >> /etc/fstab")

    script.print_section(
        f"""
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
         - scripts-per-instance
         - [ scripts-user, once ]
         - [ ssh-authkey-fingerprints, once ]
         - [ keys-to-console, once ]
         - [ install-hotplug, once ]
         - [ phone-home, once ]
         - final-message
         - power-state-change
        EOF
        """
    )

    if options.encrypt:
        script.print_section(
            """
            cat <<'EOF' >/var/lib/cloud/scripts/per-instance/resize-ephemeral-disk.sh
            #!/bin/bash
            set -xueo pipefail
            sgdisk /dev/sda -e
            sgdisk /dev/sda -d 5 -n 0:0:0 -t 0:8309 -c 0:ephemeral
            partprobe
            cryptsetup resize ephemeral
            # The above command will attempt to unmount the filesystem
            mount /dev/mapper/ephemeral || true
            resize2fs /dev/mapper/ephemeral
            EOF
            chmod +x /var/lib/cloud/scripts/per-instance/resize-ephemeral-disk.sh
            """
        )
    else:
        script.print_section(
            """
            cat <<'EOF' >/var/lib/cloud/scripts/per-instance/resize-ephemeral-disk.sh
            #!/bin/bash
            set -xueo pipefail
            sgdisk /dev/sda -e -d 4 -n 0:0:0 -t 0:8300 -c 0:ephemeral
            partprobe
            resize2fs /dev/sda4
            EOF
            chmod +x /var/lib/cloud/scripts/per-instance/resize-ephemeral-disk.sh
            """
        )

    if options.encrypt:
        script.print_section(
            """
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -yq
            apt-get install -yq cryptsetup-initramfs

            mkdir -p /etc/luks
            chmod 0700 /etc/luks
            cp /run/keyfile /etc/luks/root.keyfile
            echo "UMASK=0077" >> /etc/initramfs-tools/initramfs.conf
            echo "KEYFILE_PATTERN=/etc/luks/*.keyfile" >> /etc/cryptsetup-initramfs/conf-hook
            echo 'sdb_crypt /dev/sdb /etc/luks/root.keyfile luks,discard' >> /etc/crypttab
            cat <<EOF > /etc/crypttab
            # <target name> <source device>         <key file>      <options>
            sdb_crypt /dev/sdb /etc/luks/root.keyfile luks,discard
            ephemeral PARTLABEL=ephemeral /etc/luks/root.keyfile luks,discard,tmp
            swap PARTLABEL=swap /etc/luks/root.keyfile luks,discard,swap
            EOF
            update-initramfs -u -k all
            """
        )
    else:
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
        for i in dev sys tmp run proc; do
            mount --rbind /$i /mnt/$i
        done

        chroot /mnt /bin/bash -s <<'EXIT_CHROOT'
        set -uexo pipefail

        mkdir -p /etc/luks
        chmod 0700 /etc/luks
        cp /run/keyfile /etc/luks/root.keyfile

        # Stage1 fstab
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
        echo stage1 > /etc/hostname

        # Update the bootloader
        sed -ie '/GRUB_GFXMODE/s/.*/GRUB_GFXPAYLOAD_LINUX=1024x768x24/' /etc/default/grub
        update-grub
        grub-install /dev/sda

        passwd -d root

        # Set up the motd
        chmod -x /etc/update-motd.d/*
        cat <<EOF > /etc/motd

        Welcome to the stage1 rescue system. To continue to normal boot,
        populate the file /run/keyfile with the decryption key, then run
        ps-kexec.

          echo -n 'secretpassword' > /run/keyfile
          ps-kexec

        EOF

        export DEBIAN_FRONTEND=noninteractive
        apt-get update -yq
        apt-get install -yq kexec-tools

        cat <<EOF > /usr/local/bin/ps-kexec
        #!/bin/sh
        cryptsetup open --key-file=/run/keyfile /dev/sdb sdb_crypt
        mount /dev/mapper/sdb_crypt /mnt -o ro
        kexec -l /mnt/boot/vmlinuz --initrd=/mnt/boot/initrd.img --append="root=/dev/mapper/sdb_crypt ro consoleblank=0 systemd.show_status=true"
        systemctl kexec
        EOF
        chmod +x /usr/local/bin/ps-kexec
        """
    )

    if options.keyscript is not None:
        keyscript = pathlib.Path(options.keyscript).read_text().strip()
        script.print(
            f"cat <<'KEYSCRIPT_END' > /usr/local/bin/keyscript\n{keyscript}\nKEYSCRIPT_END\nchmod +x /usr/local/bin/keyscript"
        )
        script.print_section(
            """
            cat <<EOF > /etc/systemd/system/ps-kexec.service
            [Unit]
            Description="Stage1 Kexec"

            [Service]
            Type=oneshot
            ExecStart=/usr/local/bin/keyscript
            ExecStart=/usr/local/bin/ps-kexec
            RemainAfterExit=yes

            [Install]
            WantedBy=multi-user.target
            EOF
            systemctl enable ps-kexec
            """
        )

    script.print_section(
        """
        EXIT_CHROOT

        umount -Rl /mnt
        """
    )

    return script.getvalue()
