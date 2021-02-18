#!/bin/bash
set -ux

base=$(dirname $(realpath "${BASH_SOURCE[0]}"))
export ANSIBLE_CONFIG="${base}/cfg/ansible.cfg"
export ANSIBLE_HOST_KEY_CHECKING=False
export HOST_PATTERN_MISMATCH=ignore
export ssh_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
export os_ver="centos-8.2"
export host_mach="g9"
export path="/disks"

# drivers="/home/rmr/kubernetes/kubernetes-operator/ofs-package/fpga-ofs-centos82-lc.0.0.r8.gb110e5e.sh"
drivers="/net/bohr/var/fiberblaze/releases/lightningcreek/release_0_0_3/silicom-ofs-package-0.3.sh"
common_args="drivers=${drivers} base=${base} out_dir=${base} host_mach=${host_mach} os_ver=${os_ver} path=${path}"
common_args="${common_args} provision=${base}/files/provision.sh opae_install=${base}/files/install-opae.sh firstboot=${base}/files/firstboot.sh "
playbooks=${base}/playbooks

[ -f ${base}/admin.conf ] && rm -f ${base}/admin.conf
[ -f ${base}/join.sh ] && rm -f ${base}/join.sh

hostname_prefix="${host_mach}-$(echo -n $os_ver | tr "." "-")"
worker_prefix="${hostname_prefix}-worker"
master_hostname="${hostname_prefix}-master"

###
### Start Master
###
ansible-playbook -i ${base}/inventory \
                --ssh-extra-args="$ssh_args" \
                --extra-vars="${common_args} hostname=${master_hostname}"  \
                ${playbooks}/cleanup.yaml

for i in {1..2}
do
    ansible-playbook -i ${base}/inventory \
                     --ssh-extra-args="$ssh_args" \
                     --extra-vars="${common_args} hostname=${worker_prefix}${i}"  \
                     ${playbooks}/cleanup.yaml
done

ansible-playbook -i ${base}/inventory \
                --ssh-extra-args="$ssh_args" \
                --extra-vars="${common_args} hostname=${master_hostname}" \
                ${playbooks}/create-vm.yaml

ansible-playbook -i ${base}/inventory \
                 --ssh-extra-args="$ssh_args" \
                 --extra-vars="${common_args} hostname=${master_hostname}" \
                 ${playbooks}/copy-files.yaml

ansible-playbook -i ${base}/inventory \
                 --ssh-extra-args="$ssh_args" \
                 --extra-vars="${common_args} hostname=${master_hostname}" \
                 ${playbooks}/provision-node.yaml

ansible-playbook -i ${base}/inventory \
                 --ssh-extra-args="$ssh_args" \
                 --extra-vars="${common_args} hostname=${master_hostname} host_device=true" \
                 ${playbooks}/install-vm.yaml

ansible-playbook -i ${base}/inventory \
                 --ssh-extra-args="$ssh_args" \
                 --extra-vars="${common_args} hostname=${master_hostname} vm_state=start" \
                 ${playbooks}/vm-control.yaml

ansible-playbook -i ${base}/inventory \
                 --ssh-extra-args="$ssh_args" \
                 --extra-vars="${common_args} hostname=${master_hostname} script=/root/install-opae.sh" \
                 ${playbooks}/run-script.yaml

ansible-playbook -i ${base}/inventory \
                 --ssh-extra-args="$ssh_args" \
                 --extra-vars="${common_args} hostname=${master_hostname} vm_state=shutdown" \
                 ${playbooks}/vm-control.yaml

ansible-playbook -i ${base}/inventory \
                     --ssh-extra-args="$ssh_args" \
                     --extra-vars="${common_args} clone_in=${master_hostname} clone_out=${master_hostname}-clone"  \
                     ${playbooks}/clone-img.yaml

for i in {1..2}
do
    ansible-playbook -i ${base}/inventory \
                     --ssh-extra-args="$ssh_args" \
                     --extra-vars="${common_args} clone_in=${master_hostname} clone_out=${worker_prefix}${i}"  \
                     ${playbooks}/clone-img.yaml
done

ansible-playbook -i ${base}/inventory \
                 --ssh-extra-args="$ssh_args" \
                 --extra-vars="${common_args} hostname=${master_hostname} vm_state=start" \
                 ${playbooks}/vm-control.yaml

ansible-playbook -i ${base}/inventory \
                 --ssh-extra-args="$ssh_args" \
                 --extra-vars="${common_args} hostname=${master_hostname} script=/root/firstboot.sh" \
                 ${playbooks}/run-script.yaml

ansible-playbook -i ${base}/inventory \
                 --ssh-extra-args="$ssh_args" \
                 --extra-vars="${common_args} hostname=${master_hostname} script='fpgainfo phy'" \
                 ${playbooks}/run-script.yaml

ansible-playbook -i ${base}/inventory \
                 --ssh-extra-args="$ssh_args" \
                 --extra-vars="${common_args} hostname=${master_hostname}" \
                 ${playbooks}/get-join-creds.yaml

cp -v ${playbooks}/admin.conf $HOME/.kube/config

for i in {1..2}
do
    ansible-playbook -i ${base}/inventory \
                    --ssh-extra-args="$ssh_args" \
                    --extra-vars="${common_args} hostname=${worker_prefix}${i}" \
                    ${playbooks}/install-vm.yaml

    ansible-playbook -i ${base}/inventory \
                    --ssh-extra-args="$ssh_args" \
                    --extra-vars="${common_args} hostname=${worker_prefix}${i} vm_state=start" \
                    ${playbooks}/vm-control.yaml

    ansible-playbook -i ${base}/inventory \
                    --ssh-extra-args="$ssh_args" \
                    --extra-vars="${common_args} hostname=${worker_prefix}${i}" \
                    ${playbooks}/copy-join.yaml

    ansible-playbook -i ${base}/inventory \
                    --ssh-extra-args="$ssh_args" \
                    --extra-vars="${common_args} hostname=${worker_prefix}${i} script=/root/join.sh" \
                    ${playbooks}/run-script.yaml

    ansible-playbook -i ${base}/inventory \
                    --ssh-extra-args="$ssh_args" \
                    --extra-vars="${common_args} hostname=${worker_prefix}${i} script='kubectl cluster-info'" \
                    ${playbooks}/run-script.yaml
done