#!/bin/bash

set +x

cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

# Create the .conf file to load the modules at bootup
cat <<EOF | tee /etc/modules-load.d/crio.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Set up required sysctl params, these persist across reboots.
cat <<EOF | tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system

echo "swapoff -a" >> /etc/rc.local
chmod +x /etc/rc.local

#
# https://kubernetes.io/docs/setup/production-environment/container-runtimes/
#
# mkdir -p /etc/docker/
# cat <<EOF | tee /etc/docker/daemon.json
# {
#   "exec-opts": ["native.cgroupdriver=systemd"],
#   "insecure-registries":["docker.silicom.dk:5000"]
# }
# EOF

sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
sed -i '/swap/d' /etc/fstab
swapoff -a

dnf clean packages -y
dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm

if $(grep -q "8.2.2004" /etc/redhat-release); then
  dnf install -y https://vault.centos.org/8.2.2004/BaseOS/x86_64/os/Packages/kernel-devel-4.18.0-193.el8.x86_64.rpm
  rm /lib/modules/4.18.0-193.6.3.el8_2.x86_64/build
  ln -s  /usr/src/kernels/4.18.0-193.el8.x86_64 /lib/modules/4.18.0-193.6.3.el8_2.x86_64/build
else
  dnf install -y kernel-devel
fi

systemctl disable firewalld
systemctl stop firewalld

#
# This update will ensure the newest kernel will match
# the newest kernel-devel package on firstboot
#
export OS=CentOS_8
export VERSION=1.20
curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/devel:kubic:libcontainers:stable.repo
curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo

dnf install -y pciutils \
               kubelet \
               kubeadm \
               kubectl \
               python3 \
               cri-o \
               podman \
               tc --disableexcludes=kubernetes


sed -i 's/Wants=network-online.target/Wants=docker.socket crio.service/g' /usr/lib/systemd/system/kubelet.service
systemctl daemon-reload

mkdir -p /etc/crio/crio.conf.d

cat <<EOF | tee /etc/crio/crio.conf.d/01-log-level.conf
[crio.runtime]
log_level = "info"
EOF

cat <<EOF | tee /etc/crio/crio.conf.d/02-cgroup-manager.conf
[crio.runtime]
conmon_cgroup = "pod"
cgroup_manager = "cgroupfs"
EOF

cat <<EOF | tee /etc/crio/crio.conf.d/03-registries.conf
[registries.search]
registries = ['registry.access.redhat.com', 'registry.fedoraproject.org', 'quay.io', 'docker.io']

[registries.insecure]
registries = ['docker.silicom.dk:5000']

[registries.block]
registries = []
EOF

cat <<EOF | tee /etc/containers/registries.conf
[registries.search]
registries = ['registry.access.redhat.com', 'registry.fedoraproject.org', 'quay.io', 'docker.io']

[registries.insecure]
registries = ['docker.silicom.dk:5000']

[registries.block]
registries = []
EOF

systemctl enable cri-o
systemctl start cri-o
