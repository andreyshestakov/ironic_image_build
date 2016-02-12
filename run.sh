#!/bin/bash -xe

MYSELF="${0##*/}"
#SAVE_TEMPS=yes
#BOOTSTRAP_INCLUDE="apt-transport-https"
bindir=$(pwd)
datadir="${bindir}/configs"
# Choose name of the image and torrent file:
IMAGE_NAME=${IMAGE_NAME:-bootstrap}

[ -z "$DISTRO_RELEASE" ] && DISTRO_RELEASE="trusty"
[ -z "$MIRROR_DISTRO" ] && MIRROR_DISTRO="http://ua.archive.ubuntu.com/ubuntu/"
[ -z "$KERNEL_FLAVOR" ] && KERNEL_FLAVOR="-generic-lts-trusty"
[ -z "$ARCH" ] && ARCH="amd64"
[ -z "$DESTDIR" ] && DESTDIR=$(pwd)
[ -z "$SSHKEY" ] && SSHKEY=${DESTDIR}/id_rsa.pub

# Binaries to copy to initramfs image
BINARIES_FOR_INITRAMFS="/usr/bin/aria2c /usr/bin/pixz"

# Kernel, firmware:
BOOTSTRAP_PKGS="ubuntu-minimal linux-image${KERNEL_FLAVOR} linux-firmware linux-firmware-nonfree"
# Compressors:
BOOTSTRAP_PKGS="$BOOTSTRAP_PKGS xz-utils pixz"
# Smaller tools providing the standard ones.
# Disk managment tools
BOOTSTRAP_PKGS="$BOOTSTRAP_PKGS lvm2 parted"
# Networking tools
BOOTSTRAP_PKGS="$BOOTSTRAP_PKGS udhcpc"
# Debug packages:
#BOOTSTRAP_PKGS="$BOOTSTRAP_PKGS strace gdb lsof"
# Performance tunning:
#BOOTSTRAP_PKGS="$BOOTSTRAP_PKGS i7z powertop cpufrequtils"
# Monitoring packages:
#BOOTSTRAP_PKGS="$BOOTSTRAP_PKGS htop sysstat atop"
# Network troubleshooting:
#BOOTSTRAP_PKGS="$BOOTSTRAP_PKGS arping tcpdump arpwatch bridge-utils nfs-common netcat socat telnet"
# Hardware tools:
#BOOTSTRAP_PKGS="$BOOTSTRAP_PKGS usbutils pciutils"
# What you need
BOOTSTRAP_PKGS="$BOOTSTRAP_PKGS openssh-client openssh-server python2.7-minimal aria2 ca-certificates"
# BIOS
BOOTSTRAP_PKGS="$BOOTSTRAP_PKGS biosdevname dmidecode"
# For i40e and dkms
#BOOTSTRAP_PKGS="$BOOTSTRAP_PKGS dkms linux-headers${KERNEL_FLAVOR}"

REMOVE_PKGS="grub-common* grub-gfxpayload-lists* grub-pc* grub-pc-bin* grub2-common* libx11-6 libx11-data xauth python3.4*"

apt_setup ()
{
        local root="$1"
        local sources_list="${root}/etc/apt/sources.list"
        local sources_list_d="${root}/etc/apt/sources.list.d"
        local apt_prefs="${root}/etc/apt/preferences"

        mkdir -p "${sources_list%/*}"
        mkdir -p "${sources_list_d%/*}"

        cat > "$sources_list" <<-EOF
deb $MIRROR_DISTRO ${DISTRO_RELEASE}         main universe multiverse restricted
deb $MIRROR_DISTRO ${DISTRO_RELEASE}-security main universe multiverse restricted
deb $MIRROR_DISTRO ${DISTRO_RELEASE}-updates  main universe multiverse restricted
EOF
}

run_apt_get ()
{
        local root="$1"
        shift
        chroot "$root" env \
                LC_ALL=C \
                DEBIAN_FRONTEND=noninteractive \
                DEBCONF_NONINTERACTIVE_SEEN=true \
                TMPDIR=/tmp \
                TMP=/tmp \
                apt-get $@
}

run_debootstrap ()
{
        local root="$1"
        [ -z "$root" ] && exit 1
        local insecure="--no-check-gpg"
        local extractor=''
        [[ ! -z "$BOOTSTRAP_INCLUDE" ]] && local include="--include=$BOOTSTRAP_INCLUDE"
        env \
                LC_ALL=C \
                DEBIAN_FRONTEND=noninteractive \
                DEBCONF_NONINTERACTIVE_SEEN=true \
                debootstrap $insecure $extractor $include --arch=${ARCH} ${DISTRO_RELEASE} "$root" $MIRROR_DISTRO
}

install_packages ()
{
        local root="$1"
        shift
        echo "INFO: $MYSELF: installing pkgs: $*" >&2
        run_apt_get "$root" install --yes $@
}

remove_packages ()
{
        local root="$1"
        shift
        echo "INFO: $MYSELF: removing pkgs: $*" >&2
        run_apt_get "$root" purge --yes $@
        run_apt_get "$root" autoremove --yes
}

upgrade_chroot ()
{
        local root="$1"
        run_apt_get "$root" update
        if ! mountpoint -q "$root/proc"; then
                mount -t proc bootstrapproc "$root/proc"
        fi
        run_apt_get "$root" dist-upgrade --yes
}

make_utf8_locale ()
{
        local root="$1"
        chroot "$root" /bin/sh -c "locale-gen en_US.UTF-8 && dpkg-reconfigure locales"
}

copy_conf_files ()
{
        local root="$1"
        rsync -rlptDK "${datadir}/" "${root%/}"
        # r00tme
        sed -i $root/etc/shadow -e '/^root/c\root:$6$/wE2ubAC$XGt2igDqVAcbgELWq7GKltr0Hy6zJBioaSebR3BdmDfuPyEjCbdClQul9o2gZB3zpZvB5VN.PfDP0H.UD34SU/:15441:0:99999:7:::'
        mkdir -p $root/root/.ssh
        cat ${SSHKEY} > $root/root/.ssh/authorized_keys
        chmod -R 600 $root/root/.ssh
}

cleanup_chroot ()
{
        local root="$1"
        [ -z "$root" ] && exit 1
        signal_chrooted_processes "$root" SIGTERM
        signal_chrooted_processes "$root" SIGKILL
        umount "${root}/tmp/local-apt" 2>/dev/null || umount -l "${root}/tmp/local-apt" ||
        rm -rf $root/var/cache/apt/archives/*.deb
        rm -f $root/var/log/bootstrap.log
        rm -rf $root/boot/*
        rm -rf $root/tmp/*
        rm -rf $root/run/*
}

generate_initramfs ()
{
        local root="$1"
        initrd=${root}/tmp/initrd.gz
        wget -O ${initrd} ${MIRROR_DISTRO}/dists/${DISTRO_RELEASE}/main/installer-${ARCH}/current/images/netboot/ubuntu-installer/${ARCH}/initrd.gz
        tmp_initrd_dir=$root/tmp/initramfs
        mkdir -p ${tmp_initrd_dir}
        cd ${tmp_initrd_dir}
        gzip -dc ${initrd} | cpio -id
        for BINARY in ${BINARIES_FOR_INITRAMFS}
        do
                cp -f ${root}/${BINARY} ${tmp_initrd_dir}/bin/ 2>/dev/null || echo "no bin"
                for BINARY_LIB in $(ldd ${root}/${BINARY} | awk '{print $3}' | grep ^/)
                do
                        cp -f ${root}/${BINARY_LIB} ${tmp_initrd_dir}/lib/ 2>/dev/null || echo "no lib"
                done
        done
        rsync -rlptDK "${datadir}_initramfs/" "${tmp_initrd_dir}/"
        find . | cpio -H newc -o | pixz > ${DESTDIR}/initrams.img.xz
}

copy_vmlinuz ()
{
        local root="$1"
        linux=${DESTDIR}/linux
        wget -O ${linux} ${MIRROR_DISTRO}/dists/${DISTRO_RELEASE}/main/installer-${ARCH}/current/images/netboot/ubuntu-installer/${ARCH}/linux
}

mk_targz_image ()
{
        local root="$1"
        CURRENT_DIRECTORY=`pwd`
        cd $root
        tar -Ipixz -cf ${DESTDIR}/${IMAGE_NAME}.tar.xz ./
}

build_image ()
{
        local root="$1"
        chmod 755 "$root"
        run_debootstrap "$root"
        make_utf8_locale "$root"
        apt_setup "$root"
        upgrade_chroot "$root"
        install_packages "$root" $BOOTSTRAP_PKGS
        remove_packages "$root" $REMOVE_PKGS
        copy_conf_files "$root"
        generate_initramfs "$root"
        copy_vmlinuz "$root"
        cleanup_chroot "$root"
        final_cleanup "$root"
        mk_targz_image "$root"
}

root=`mktemp -d --tmpdir bootstrap-image.XXXXXXXXX`

main ()
{
        build_image "$root"
}

signal_chrooted_processes ()
{
        local root="$1"
        local signal="${2:-SIGTERM}"
        local max_attempts=10
        local timeout=2
        local count=0
        local found_processes
        [ ! -d "$root" ] && return 0
        while [ $count -lt $max_attempts ]; do
                found_processes=''
                for pid in `fuser $root 2>/dev/null`; do
                        [ "$pid" = "kernel" ] && continue
                        if [ "`readlink /proc/$pid/root`" = "$root" ]; then
                                found_processes='yes'
                                kill "-${signal}" $pid
                        fi
                done
                [ -z "$found_processes" ] && break
                count=$((count+1))
                sleep $timeout
        done
}

final_cleanup ()
{
        signal_chrooted_processes "$root" SIGTERM
        signal_chrooted_processes "$root" SIGKILL
        for mnt in /tmp/local-apt /mnt/dst /mnt/src /mnt /proc; do
                if mountpoint -q "${root}${mnt}"; then
                        umount "${root}${mnt}" || umount -l "${root}${mnt}" || true
                fi
        done
}

main
trap final_cleanup HUP TERM INT QUIT
if [ -z "$SAVE_TEMPS" ]; then
        rm -rf "$root"
fi
