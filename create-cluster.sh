#!/bin/bash

set -x

out_dir=${1:-$(pwd)}

init() {
    if [ ! -d ofs-package ] ; then
        git clone --recursive --branch development ssh://rmr@bohr.silicom.dk/var/fiberblaze/Revision/git/Fiberblaze/sw/Intel/ofs-package.git
        make -C ofs-package
    fi

    [ ! -e silicom-ofs-package.sh ] && cp ofs-package/silicom-ofs-package.sh .
}

cleanup() {
    state="$(virsh list --all | grep $1 | awk '{ print $3 }')"
    if [ "${state}" = "running" ] || [ "${state}" = "shut" ] ; then
        virsh destroy $1
    fi
    if $(virsh list --all | grep -q $1); then
        virsh undefine $1
    fi

    [ -f $out_dir/$1.img ] && rm -f $out_dir/$1.img

    [ -f firstboot-join.sh ] && rm -f firstboot-join.sh
}

setup_master_img() {
    virt-builder centos-8.2 -o $out_dir/master.img --root-password password:123456 --selinux-relabel
    virt-customize -a $out_dir/master.img --hostname "master" --root-password password:123456
    virt-customize -a $out_dir/master.img --copy-in provision.sh:/root --root-password password:123456
    virt-customize -a $out_dir/master.img --copy-in silicom-ofs-package.sh:/root --root-password password:123456
    virt-customize -a $out_dir/master.img --run-command '/root/provision.sh' --root-password password:123456
}

setup_worker_img() {
    virt-clone --original master --name worker$1 --auto-clone --file $out_dir/worker$1.img
    virt-customize -a $out_dir/worker$1.img --hostname "worker$1" --root-password password:123456
    virt-customize -a $out_dir/worker$1.img --run-command "sed -i 's/master/worker$1/g' /etc/hosts" --root-password password:123456
    virt-customize -a $out_dir/worker$1.img --run-command "/bin/rm -v /etc/ssh/ssh_host_*" --root-password password:123456
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
                 --disk path=$out_dir/master.img,format=raw \
                 --os-variant auto \
                 --virt-type kvm \
                 --vcpus 4 \
                 --accelerate \
                 --import \
                 --noautoconsole \
                 --nographics
                #--host-device=pci_8086_10bd

    sleep 2
    while ! $(virsh list --state-running | grep -q master); do
        echo "Waiting for master to run"
        sleep 2
    done

    virsh shutdown master
    while ! $(virsh list --state-shutoff | grep -q master); do
        virsh shutdown master
        echo "Waiting for master to shutdown"
        sleep 5
    done        
}

wait_for_master_startup() {
    virt-customize -a $out_dir/master.img --firstboot firstboot.sh --root-password password:123456
    virsh start master

    while ! $(virt-ls master / | grep -q join.sh); do
        echo "Waiting for master join script."
        sleep 60;
    done

    sync
    virt-copy-out -a $out_dir/master.img /join.sh .

cat > firstboot-join.sh << EOF
#!/bin/bash

set -xe

export HOME=/root

while ! \$(ping -q -c 1 -W 5 8.8.8.8 > /dev/null 2>&1); do
    logger 'No network'
    sleep 1;    
done

while ! \$(docker info > /dev/null 2>&1); do
    logger 'No docker'
    sleep 1;    
done

dnf install -y kernel-devel
yes | /root/silicom-ofs-package.sh

$(cat join.sh) --v=5

mkdir -p /root/.kube
cp -i /etc/kubernetes/kubelet.conf /root/.kube/config
    
EOF
    virt-customize -a $out_dir/worker1.img --firstboot firstboot-join.sh --root-password password:123456
    virt-customize -a $out_dir/worker2.img --firstboot firstboot-join.sh --root-password password:123456
    virt-copy-out -a $out_dir/master.img /etc/kubernetes/admin.conf .
}

start_worker() {
    virsh start worker$1
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
