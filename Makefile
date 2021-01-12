create:
	virt-builder fedora-32 --root-password password:123456 --selinux-relabel
	virt-customize -a fedora-32.img --run-command 'dnf update -y' --root-password password:123456 -v
	virt-customize -a fedora-32.img --run-command 'dnf install podman -y' --root-password password:123456
	# virt-customize -a fedora-32.img --run-command 'dnf install @container-tools -y' --root-password password:123456
	virt-customize -a fedora-32.img --run-command 'dnf install kubernetes -y' --root-password password:123456

clean:
	virsh destroy master
	virsh destroy slave1
	virsh destroy slave2

undef: clean
	virsh undefine master
	virsh undefine slave1
	virsh undefine slave2
