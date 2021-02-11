#!/bin/bash

base=$(dirname $(realpath "${BASH_SOURCE[0]}"))

cat << EOF > $base/playbooks/group_vars/vars
# Where they will be installed, needs libvirt
host_mach: g9

drivers: /net/bohr/var/fiberblaze/releases/lightningcreek/release_0_0_3/silicom-ofs-package-0.3.sh

host_dir: /disks

os_ver: centos-8.2

# These three paths will need to be relative
files_to_copy:
    - $base/files/provision.sh
    - $base/files/install-opae.sh
    - $base/files/kubeadmin-init.sh
EOF
