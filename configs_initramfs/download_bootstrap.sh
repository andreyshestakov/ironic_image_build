#!/bin/sh -xe

# Open second ssh console
sh < /dev/tty2 > /dev/tty2 2>/dev/null &

# Get parameters from kernel options
BOOTSTRAP_LINK=$(for OPTION in `cat /proc/cmdline`; do echo $OPTION; done | grep ^bootstrap_link= | cut -d"=" -f2)
BOOTSTRAP_FILENAME=$(for OPTION in `cat /proc/cmdline`; do echo $OPTION; done | grep ^bootstrap_filename= | cut -d"=" -f2)

# Configure networking
ip link set lo up
for IF in $(ls -1 /sys/class/net | grep -v lo)
    do
        udhcpc -i ${IF} -n -t3 -T1 || echo "Can not get address on " ${IF}
    done

# Download ubuntu image via torrent
mkdir -p /tmp/bootstrap
/bin/aria2c --log=/aria2c.log \
            --on-download-complete=/run_bootstrap.sh \
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
            --out=${BOOTSTRAP_FILENAME} \
            ${BOOTSTRAP_LINK}

# Wait infinity
tail -f /dev/null
