#!/bin/sh -xe

BOOTSTRAP_FILENAME=$(for OPTION in `cat /proc/cmdline`; do echo $OPTION; done | grep ^bootstrap_filename= | cut -d"=" -f2)

# Unarchive bootstrap image
mkdir /bootstrap
pixz -d < /tmp/bootstrap/${BOOTSTRAP_FILENAME} | tar -C /bootstrap -xf -

# Mount needed for chroot file systems
mount -t sysfs /sys /bootstrap/sys
mount -t proc /proc /bootstrap/proc
mount -o bind /dev /bootstrap/dev
mount -t devpts none /bootstrap/dev/pts

# DNS
rm -f /bootstrap/etc/resolv.conf
cp /etc/resolv.conf /bootstrap/etc/resolv.conf
hostname -F /bootstrap/etc/hostname

# Start SSH
chroot /bootstrap service ssh start
