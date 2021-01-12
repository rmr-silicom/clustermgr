== Use libvirt

== Fedora 32

Setup base image for all nodes including master.

virt-builder fedora-32 --root-password password:123456 --update --selinux-relabel
virt-customize -a fedora-32.img --run-command 'dnf update -y' --root-password password:123456
virt-customize -a fedora-32.img --run-command 'dnf install podman -y' --root-password password:123456
virt-customize -a fedora-32.img --run-command 'dnf install @container-tools -y' --root-password password:123456
virt-customize -a fedora-32.img --run-command 'dnf install kubernetes -y' --root-password password:123456

Clone VM template into 3 VMs, where there are 2 nodes and 1 master.

virt-install --name f32vm1 --ram 2048 --disk path=fedora-32.img,format=raw --os-variant fedora28 --import --nographics

== Fedora 33 (Base cloud images https://alt.fedoraproject.org/cloud/)
virt-builder fedora-33 --root-password password:123456 --update --selinux-relabel
virt-customize -a fedora-33.img --run-command 'dnf update -y' --root-password password:123456
virt-customize -a fedora-33.img --run-command 'dnf install podman -y' --root-password password:123456
virt-customize -a fedora-33.img --run-command 'dnf install @container-tools -y' --root-password password:123456
virt-customize -a fedora-33.img --run-command 'dnf install kubernetes -y' --root-password password:123456

== RHEL8 specific

RHEL8 image is not part of the libvirt repos. So we need to include the xz base image as a local file.

curl https://download.fedoraproject.org/pub/fedora/linux/releases/33/Cloud/x86_64/images/Fedora-Cloud-Base-33-1.2.x86_64.raw.xz -o /home/rmr/builder/

cat << EOF > /etc/virt-builder/repos.d/local.conf
[local]
uri=file:///home/rmr/builder/index
proxy=off
EOF

cat << EOF > /home/rmr/builder/index
[Fedora-33]
name=Fedora-33
arch=x86_64
file=Fedora-Cloud-Base-33-1.2.x86_64.raw.xz
notes=Fedora 33 from Silicom Denmark A/S
size=203308980
compressed_size=203308980
expand=/dev/sda3
EOF

== Start each of the machines
virsh start master
virsh start slave1
virsh start slave2

== Force guest to stop
virsh destroy master
virsh destroy slave1
virsh destroy slave2

virsh undefine master
virsh undefine slave1
virsh undefine slave2

== Connect to VM

virsh --connect qemu:///system start f32vm1



