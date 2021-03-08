#!/bin/bash

#
# https://kxr.me/2019/08/17/openshift-4-upi-install-libvirt-kvm/
#


#
# https://getfedora.org/en/coreos/download?tab=metal_virtualized&stream=stable
#

set -xe

BASE=$(dirname $(realpath "${BASH_SOURCE[0]}"))

WEB_PORT=8080
HOST_IP=$(ip a | grep -m 1 10.100 | awk '{print $2}' | sed 's/\/.*//')
ignition_url=http://${HOST_IP}:${WEB_PORT}
cluster_name="openshift"
base_domain="local"
VCPUS="8"
RAM_MB="16000"
DISK_GB="30"
install_dir=$BASE/install_dir
fcos_ver="33.20210217.3.0"
fedora_base="https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${fcos_ver}/x86_64/fedora-coreos-${fcos_ver}"
image_url=${fedora_base}-metal.x86_64.raw.xz
rootfs_url=${fedora_base}-live-rootfs.x86_64.img
WORKERS="0"
MASTERS="3"
IMAGE="$BASE/fedora-coreos-${fcos_ver}-live.x86_64.iso"

INSTALLER=$BASE/bin/openshift-install
OC=$BASE/bin/oc

start_fileserver() {
  if $(docker ps | grep "static-file-server" > /dev/null 2>&1) ; then
      docker rm -f static-file-server
  fi

  docker run -d --name static-file-server --rm  -v ${install_dir}:/web -p ${WEB_PORT}:${WEB_PORT} -u $(id -u):$(id -g) halverneus/static-file-server:latest
  sleep 1
  curl ${HOST_IP}:8080/master.ign -s > /dev/null
}

cleanup() {

#  podman run --pull=always -i --rm -v $BASE:/data -w /data  \
#              quay.io/coreos/coreos-installer:release download -s stable -p qemu -f qcow2.xz --decompress

  if [ ! -e $IMAGE ] ; then
#    podman run --privileged --pull=always --rm -v $BASE:/data -w /data \
#        quay.io/coreos/coreos-installer:release download -s stable -p metal -f iso

    wget https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${fcos_ver}/x86_64/fedora-coreos-${fcos_ver}-live.x86_64.iso -O ${IMAGE}
  fi

  [ ! -e $BASE/bin ] && mkdir -p $BASE/bin

  if [ ! -e $BASE/bin/openshift-install ] ; then
    wget https://github.com/openshift/okd/releases/download/4.6.0-0.okd-2021-02-14-205305/openshift-install-linux-4.6.0-0.okd-2021-02-14-205305.tar.gz
    tar xvf openshift-install-linux-4.6.0-0.okd-2021-02-14-205305.tar.gz -C $BASE/bin/
    chmod +x  $BASE/bin/openshift-install
  fi

  if [ ! -e $BASE/bin/oc ] ; then
    wget https://github.com/openshift/okd/releases/download/4.6.0-0.okd-2021-01-23-132511/openshift-client-linux-4.6.0-0.okd-2021-01-23-132511.tar.gz
    tar xvf openshift-client-linux-4.6.0-0.okd-2021-01-23-132511.tar.gz -C $BASE/bin/
    chmod +x  $BASE/bin/oc
  fi

  if [ -e .openshift_install.log ] ; then
    rm .openshift_install*
  fi

  [ -e ${install_dir} ] && rm -rf ${install_dir}
  mkdir -p ${install_dir}

cat <<EOF > ${install_dir}/install-config.yaml
apiVersion: v1
baseDomain: ${base_domain}
compute:
- hyperthreading: Enabled
  name: worker
  replicas: ${WORKERS}
controlPlane:
  hyperthreading: Enabled
  name: master
  replicas: ${MASTERS}
metadata:
  name: ${cluster_name}
networking:
  clusterNetworks:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
fips: false
pullSecret: '{"auths":{"cloud.openshift.com":{"auth":"b3BlbnNoaWZ0LXJlbGVhc2UtZGV2K29jbV9hY2Nlc3NfMmQ2NmVjYWE0YmU0NGJlNGJmZThiNDYyODBjMTAxZDc6TDVBN0JST0laVDNWSlpHOUwyMTIwNEpENTFZWTVERjkxUjhGNDRJQk1VME1IRlpFR0FQUURCSE5aMUlESE5CUA==","email":"rmr@silicom.dk"},"quay.io":{"auth":"b3BlbnNoaWZ0LXJlbGVhc2UtZGV2K29jbV9hY2Nlc3NfMmQ2NmVjYWE0YmU0NGJlNGJmZThiNDYyODBjMTAxZDc6TDVBN0JST0laVDNWSlpHOUwyMTIwNEpENTFZWTVERjkxUjhGNDRJQk1VME1IRlpFR0FQUURCSE5aMUlESE5CUA==","email":"rmr@silicom.dk"},"registry.connect.redhat.com":{"auth":"fHVoYy1wb29sLTkwMGVkODM4LTZkZWMtNDhiNS04N2FiLTE2N2I2MTdmYWY5MDpleUpoYkdjaU9pSlNVelV4TWlKOS5leUp6ZFdJaU9pSmhOemxrTjJNeU5HTmpZMlkwWXpFNE9XUTJNVGd3WWpGalptWmpNVEE0TmlKOS5iOERUSEJuczZlQnF0ZUhfTlpta2lOcVZCcnJIRXI2ZFRia2tydzFDOTFOMUJrNHVBTGhnRTE0eE1Qd25FaXJkNWtwVXhtOFEtZlJMTERxR241amgtQVRXRlFlZmFMYy1kT25CX0hIdm5qVEZtQ3BreFVPT0hiVmI4X3FNdENIb0VOemFHc09ReEcxaG5RY0VKaXlyaXdmTUVKWk5KbGFFZExwX1I0YmlERDQ5NlhMMTNVRHlnUWpQZWZZVnBRR2xNXzlIT3VXWDVWazNtWW9zUFBROXd1cndGRjZXYjMtM1J1RGtLV0lrMVZpWWhPclpSTkZTNmJ5UWZCUjZqTVBNd2Rhc0ZmRmRnRWwwVDQ2Uk5ZaGpwMktxYVA1MDNwUHltT1dtT2NNTE5lTzJXWHc2V3VQRzZrTEphbHVkV1pUTTNabHNpTTNOc1JSZFdnblZHQmlaWWNMODBsNUVBLUUzeVBJRFlaSk1yZ0xJMkJkSXc1R2ZfT3ctaFZXY2FxczVhTVlaTC1CcmdKNG5pTVhYd2VpZFVKTlJaUjFobHBrM1JGM0hSZkU5MGNCc3FOSW5FZXM3N244VVJKX2lFZUxLc3dJQUxGU1JZWjdYWDhwWG9mU2ZyVEVkV0ZBMGY2Nk92WHRqWFIzMTdrSU9TOGx2RlduZE5iYUJPZVJQaDhibndackotWXFOdG5iMzduNkZ0TXdjUzBfVVotUjZjcGNnUUpmSjNmaG50ZTVnckR3RkpXYTh1eXRRcEFpMWt5bmhFQ2ktWGFiLVlRQ2hJTHFhdGN5Yk1SUXdzYTVfd0tBSmNaQkJHQzNrVThFeTBSVW5pUmY0aXBLLW1jaERHNjl1cXFwQ1JMS1B3SmVySm1SVE5EbUdFYnZfS3B6eGhxckVQbENXbV9TUUVkUQ==","email":"rmr@silicom.dk"},"registry.redhat.io":{"auth":"fHVoYy1wb29sLTkwMGVkODM4LTZkZWMtNDhiNS04N2FiLTE2N2I2MTdmYWY5MDpleUpoYkdjaU9pSlNVelV4TWlKOS5leUp6ZFdJaU9pSmhOemxrTjJNeU5HTmpZMlkwWXpFNE9XUTJNVGd3WWpGalptWmpNVEE0TmlKOS5iOERUSEJuczZlQnF0ZUhfTlpta2lOcVZCcnJIRXI2ZFRia2tydzFDOTFOMUJrNHVBTGhnRTE0eE1Qd25FaXJkNWtwVXhtOFEtZlJMTERxR241amgtQVRXRlFlZmFMYy1kT25CX0hIdm5qVEZtQ3BreFVPT0hiVmI4X3FNdENIb0VOemFHc09ReEcxaG5RY0VKaXlyaXdmTUVKWk5KbGFFZExwX1I0YmlERDQ5NlhMMTNVRHlnUWpQZWZZVnBRR2xNXzlIT3VXWDVWazNtWW9zUFBROXd1cndGRjZXYjMtM1J1RGtLV0lrMVZpWWhPclpSTkZTNmJ5UWZCUjZqTVBNd2Rhc0ZmRmRnRWwwVDQ2Uk5ZaGpwMktxYVA1MDNwUHltT1dtT2NNTE5lTzJXWHc2V3VQRzZrTEphbHVkV1pUTTNabHNpTTNOc1JSZFdnblZHQmlaWWNMODBsNUVBLUUzeVBJRFlaSk1yZ0xJMkJkSXc1R2ZfT3ctaFZXY2FxczVhTVlaTC1CcmdKNG5pTVhYd2VpZFVKTlJaUjFobHBrM1JGM0hSZkU5MGNCc3FOSW5FZXM3N244VVJKX2lFZUxLc3dJQUxGU1JZWjdYWDhwWG9mU2ZyVEVkV0ZBMGY2Nk92WHRqWFIzMTdrSU9TOGx2RlduZE5iYUJPZVJQaDhibndackotWXFOdG5iMzduNkZ0TXdjUzBfVVotUjZjcGNnUUpmSjNmaG50ZTVnckR3RkpXYTh1eXRRcEFpMWt5bmhFQ2ktWGFiLVlRQ2hJTHFhdGN5Yk1SUXdzYTVfd0tBSmNaQkJHQzNrVThFeTBSVW5pUmY0aXBLLW1jaERHNjl1cXFwQ1JMS1B3SmVySm1SVE5EbUdFYnZfS3B6eGhxckVQbENXbV9TUUVkUQ==","email":"rmr@silicom.dk"}}}'
sshKey: '$(cat ${BASE}/node.pub)'
EOF

  $INSTALLER create manifests --dir=${install_dir}
  $INSTALLER create ignition-configs --dir=${install_dir}

  while $(virsh list --state-running | grep -q running); do
    virsh destroy $(virsh list --state-running --name | head -n1)
  done

  while [ ! -z "$(virsh list --all --name)" ] ; do
    virsh undefine $(virsh list --all --name | head -n1) --remove-all-storage
  done

  while [ ! -z "$(ls ${BASE}/*.raw)" ] ; do
    rm -f $(ls ${BASE}/*.raw | head -n1)
    sleep 2
  done

  if $(virsh net-list | grep -q default); then
    virsh net-destroy default
    virsh net-undefine default
  fi

  virsh net-define --file ${BASE}/../files/default.xml
  virsh net-start default

  podman run --pull=always -i --rm quay.io/coreos/fcct -p -s <$BASE/../files/lb.fcc > ${install_dir}/lb.ign
}

create_vm() {
  local hostname=$1
  local disk=${BASE}/${hostname}

  qemu-img create -f raw ${disk}.raw ${DISK_GB}G
  chmod a+wr ${disk}.raw
  virt-install --connect="qemu:///system" --name="${1}" --vcpus="${VCPUS}" --memory="${2}" \
          --virt-type kvm --accelerate \
          --os-variant rhl9 \
          --network network=default,mac="$(virsh net-dumpxml default | grep $hostname | grep mac | sed "s/ name=.*//g" | sed -n "s/.*mac='\(.*\)'/\1/p")" \
          --graphics=none  --noautoconsole --noreboot \
          --disk=${disk}.raw \
          --location=${IMAGE} \
          --extra-args "nomodeset rd.neednet=1 coreos.inst=yes console=ttyS0 coreos.inst.install_dev=/dev/sda coreos.live.rootfs_url=${rootfs_url} coreos.inst.ignition_url=${ignition_url}/${3} coreos.inst.image_url=${image_url}"
}

cleanup
start_fileserver
create_vm "lb" "4096" "lb.ign"
create_vm "bootstrap" "${RAM_MB}" "bootstrap.ign"

for i in $(seq 1 $MASTERS) ; do
    create_vm "master$i" "${RAM_MB}" "master.ign"
done

for i in $(seq 1 $WORKERS) ; do
    create_vm "worker$i" "${RAM_MB}" "worker.ign"
done

while [ ! -z "$(virsh list --state-running --name)" ] ; do
  echo "waiting"
  sleep 20;
done

virsh start "lb"
while ! $(nc -v -z -w 1 lb.openshift.local 22 > /dev/null 2>&1); do
  echo "Waiting for lb"
  sleep 30
done

virsh start "bootstrap"
while ! $(nc -v -z -w 1 lb.openshift.local 6443 > /dev/null 2>&1); do
  echo "Waiting for bootstrap"
  sleep 5
done

for i in $(seq 1 $MASTERS) ; do
    virsh start "master$i"
done

for i in $(seq 1 $WORKERS) ; do
    virsh start "worker$i"
done

while ! $(nc -v -z -w 1 master$MASTERS.openshift.local 22 > /dev/null 2>&1); do
  echo "Waiting for master$MASTERS"
  sleep 30
done
date

cp install_dir/auth/kubeconfig install_dir/auth/kubeconfig.orig
export KUBECONFIG=$(pwd)/auth/kubeconfig

while ! $(ssh -i node  -o LogLevel=ERROR -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" "core@bootstrap.${cluster_name}.${base_domain}" "[ -e /opt/openshift/cco-bootstrap.done ]") ; do
  echo -n "Waiting for cco-bootstrap.done"
  sleep 30
done
date

$INSTALLER --dir=install_dir wait-for bootstrap-complete --log-level debug

while ! $(ssh -i node  -o LogLevel=ERROR -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" "core@bootstrap.${cluster_name}.${base_domain}" "[ -e /opt/openshift/cb-bootstrap.done ]") ; do
  echo -n "Waiting for cb-bootstrap.done"
  sleep 30
done
date

while ! $(ssh -i node  -o LogLevel=ERROR -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" "core@bootstrap.${cluster_name}.${base_domain}" "[ -e /opt/openshift/.bootkube.done ]") ; do
  echo -n "Waiting for .bootkube.done"
  sleep 30
done
date

echo -n "====> Removing Bootstrap from haproxy: "
ssh -i sshkey lb."${cluster_name}.${base_domain}" "sed -i '/bootstrap\.${cluster_name}\.${base_domain}/d' /etc/haproxy/haproxy.cfg"
ssh -i sshkey lb."${cluster_name}.${base_domain}" "sudo podman restart haproxy"

date
$INSTALLER --dir=install_dir wait-for bootstrap-complete --log-level debug

remove_bootstrap

virsh destroy bootstrap
virsh undefine bootstrap --remove-all-storage

$OC get csr -ojson | jq -r '.items[] | select(.status == {} ) | .metadata.name' | xargs --no-run-if-empty $OC adm certificate approve

$INSTALLER --dir=install_dir wait-for install-complete --log-level debug

KUBECONFIG=install_dir/auth/kubeconfig ./bin/oc create -f https://raw.githubusercontent.com/kubernetes-sigs/node-feature-discovery/master/nfd-daemonset-combined.yaml.template -v=8