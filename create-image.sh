#!/bin/bash

git clone --recursive ssh://rmr@bohr.silicom.dk/var/fiberblaze/Revision/git/Fiberblaze/sw/Intel/ofs-package.git
curl https://kojipkgs.fedoraproject.org//packages/kernel/5.6.8/300.fc32/x86_64/kernel-devel-5.6.8-300.fc32.x86_64.rpm -o kernel.rpm

# Create machine image which cluster will be cloned from
virt-builder fedora-32 --root-password password:123456 --selinux-relabel
virt-customize -a fedora-32.img --run-command 'dnf update -y' --root-password password:123456

virt-customize -a fedora-32.img --copy-in packages.list:/root  --root-password password:123456
virt-customize -a fedora-32.img --copy-in kernel.rpm:/root --root-password password:123456
virt-customize -a fedora-32.img --copy-in ofs-package:/root/build --root-password password:123456

virt-customize -a fedora-32.img --run-command 'cat /root/packages.list | xargs yum -y install' --root-password password:123456
virt-customize -a fedora-32.img --run-command 'rpm -i /root/kernel.rpm' --root-password password:123456
virt-customize -a fedora-32.img --run-command '/root/build/ofs-package/make-package.sh silicom-ofs-package.sh' --root-password password:123456
# PCI passthrough
# virsh nodedev-list | grep pci
# Use the PCI identifier output from the
# virsh nodedev command as the value for the --host-device parameter.
#
virt-install --name master --ram 2048 --disk path=fedora-32.img,format=raw --virt-type kvm --vcpus 2 --accelerate --import --noautoconsole
virsh suspend master
virt-clone --original master --name slave1 --auto-clone --file slave1.img
virt-clone --original master --name slave2 --auto-clone --file slave2.img
