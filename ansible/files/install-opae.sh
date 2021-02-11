#!/bin/sh

set -xe

while ! $(ping -q -c 1 -W 5 8.8.8.8 > /dev/null 2>&1); do
    logger 'No network'
    sleep 1;    
done

file=$(ls /root/silicom-ofs-package*.sh)
if [ -e $file ] ; then
    chmod +x $file
    dnf clean packages -y
    rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY*
    yes | $file
fi

touch /tmp/opae.done
