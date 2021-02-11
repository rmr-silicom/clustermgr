#!/bin/bash
# examples: https://igoipy.com/posts/2018/02/cloning-kvm-virtual-host_machines/
#
set -xu

export LIBVIRT_DEFAULT_URI=qemu:///system

out_dir=${1:-$(pwd)}

init() {
  if [ -d ofs-package ] ; then
    git clone --recursive --branch development ssh://rmr@bohr.silicom.dk/var/fiberblaze/Revision/git/Fiberblaze/sw/Intel/ofs-package.git
    make -C ofs-package
  fi

  [ ! -e silicom-ofs-package.sh ] && cp ofs-package/silicom-ofs-package.sh .
}

cleanup() {
    state="$(virsh list --all | grep $1 | awk '{ print $3 }')"
    if [ "${state}" = "running" ]; then
        virsh destroy $1
    fi
    if $(virsh list --all | grep -q $1); then
        virsh undefine $1
    fi

    [ -f $out_dir/$1.img ] && rm -f $out_dir/$1.img

    [ -f join.sh ] && rm -f join.sh
    [ -f firstboot-join.sh ] && rm -f firstboot-join.sh
}

setup_master_img() {
    if $(lsb_release -a | grep -q "CentOS Linux release 7") ; then
        dd if=$out_dir/centos-8-2-on-7.img of=$out_dir/master.img bs=1024M
    else
        virt-builder centos-8.2 -o $out_dir/master.img --root-password password:123456 --selinux-relabel
    fi

    chmod a+w $out_dir/master.img
    virt-customize -a $out_dir/master.img --hostname "master"
    virt-customize -a $out_dir/master.img --copy-in ${out_dir}/ansible/files/provision.sh:/root
    virt-customize -a $out_dir/master.img --copy-in ${out_dir}/silicom-ofs-package.sh:/root
    virt-customize -a $out_dir/master.img --copy-in ${out_dir}/ansible/files/install-opae.sh:/root
    virt-customize -a $out_dir/master.img --run-command '/root/provision.sh' -v
    # virt-customize -a $out_dir/master.img --run-command '/root/install-opae.sh'
}

setup_worker_img() {
    dd if=$out_dir/master.img of=$out_dir/worker$1.img bs=1024M
    # THIS MAKES file root owned.... virt-clone --original master --name worker$1 --auto-clone --file $out_dir/worker$1.img
    virt-customize -a $out_dir/worker$1.img --hostname "worker$1"
    virt-customize -a $out_dir/worker$1.img --run-command "sed -i 's/master/worker$1/g' /etc/hosts"
    virt-customize -a $out_dir/worker$1.img --run-command "/bin/rm -v /etc/ssh/ssh_host_*"
}

install_master() {
    #
    # https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/5/html/virtualization/sect-virtualization-adding_a_pci_device_to_a_host_with_virt_install
    # virsh nodedev-list --tree
    # virsh nodedev-list | grep pci
    #
    virt-install --name master \
                 --ram 2048 \
                 --connect qemu:///system \
                 --disk path=$out_dir/master.img,format=raw,readonly=no \
                 --os-variant fedora27 \
                 --virt-type kvm \
                 --vcpus 4 \
                 --accelerate \
                 --import \
                 --noautoconsole \
                 --nographics
                #--host-device=$(lspci -d 1c2c:1000 | awk '{ print $1 }')

    sleep 2
    while ! $(virsh list --state-running | grep -q master); do
        echo "Waiting for master to run"
        sleep 5
    done

    virsh shutdown master
    while ! $(virsh list --state-shutoff | grep -q master); do
        virsh shutdown master
        echo "Waiting for master to shutdown"
        sleep 10
    done        
}

wait_for_master_startup() {
    virt-customize -a $out_dir/master.img --firstboot ${out_dir}/ansible/files/firstboot.sh
    virsh start master

    while ! $(LIBGUESTFS_BACKEND=direct virt-ls master / | grep -q join.sh); do
        echo "Waiting for master join script."
        sleep 60;
    done

    sync
    LIBGUESTFS_BACKEND=direct virt-copy-out -a $out_dir/master.img /join.sh .

    virt-customize -a $out_dir/worker1.img --firstboot join.sh --root-password password:123456
    virt-customize -a $out_dir/worker2.img --firstboot join.sh --root-password password:123456
    LIBGUESTFS_BACKEND=direct virt-copy-out -a $out_dir/master.img /etc/kubernetes/admin.conf .
}

start_worker() {
    virt-install --name worker$1 \
                 --ram 2048 \
                 --connect qemu:///system \
                 --disk path=$out_dir/worker$1.img,format=raw \
                 --os-variant fedora27 \
                 --virt-type kvm \
                 --vcpus 4 \
                 --accelerate \
                 --import \
                 --noautoconsole \
                 --nographics
    echo "WORKER$1 MAC: $(virsh dumpxml worker${1} | fgrep -i "mac address" | awk -F"'" '{ print $2 }')"
}

cleanup master
cleanup worker1
cleanup worker2

init
setup_master_img
install_master
setup_worker_img 1
setup_worker_img 2
wait_for_master_startup
start_worker 1
start_worker 2
sleep 20
ip neigh
