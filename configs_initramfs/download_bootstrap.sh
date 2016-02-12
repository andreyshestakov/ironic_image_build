#!/bin/sh -xe

# Get parameters from kernel options
SQUASHFS_LINK=$(for OPTION in `cat /proc/cmdline`; do echo $OPTION; done | grep ^fetch= | cut -d"=" -f2-)
SQUASHFS_FILENAME=$(for OPTION in `cat /proc/cmdline`; do echo $OPTION; done | grep ^squashfs_filename= | cut -d"=" -f2-)

# Download ubuntu image via torrent
mkdir -p /tmp/bootstrap
/bin/aria2c --log=/aria2c.log \
            --on-bt-download-complete=/run_bootstrap.sh \
            --check-certificate=false \
            --check-integrity=true \
            --bt-enable-lpd=true \
            --seed-ratio=0.0 \
            --seed-time=999 \
            --bt-tracker-interval=5 \
            --enable-dht=false \
            --enable-dht6=false \
            --follow-torrent=mem \
            --dir=/tmp/bootstrap \
            --out=${SQUASHFS_FILENAME} \
            ${SQUASHFS_LINK} &&
/run_bootstrap.sh
