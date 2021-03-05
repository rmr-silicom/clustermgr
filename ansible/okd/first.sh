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
VCPUS="4"
RAM_MB="8192"
DISK_GB="10"
install_dir=$BASE/install_dir
fcos_ver="33.20210217.3.0"
fedora_base="https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${fcos_ver}/x86_64/fedora-coreos-${fcos_ver}"
image_url=${fedora_base}-metal.x86_64.raw.xz
rootfs_url=${fedora_base}-live-rootfs.x86_64.img
WORKERS="0"
MASTERS="3"
IMAGE="$BASE/fedora-coreos-${fcos_ver}-live.x86_64.iso"

INSTALLER=$BASE/bin/openshift-install
if [ -e /usr/local/bin/openshift-install ] ; then
  INSTALLER=/usr/local/bin/openshift-install
fi

OC=$BASE/bin/oc
if [ -e /usr/local/bin/oc ] ; then
  OC=/usr/local/bin/oc
fi

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

  [ -e ${install_dir} ] && rm -rf ${install_dir}
  mkdir -p ${install_dir}

cat <<EOF > ${install_dir}/install-config.yaml
apiVersion: v1
baseDomain: ${base_domain}
compute:
- hyperthreading: Disabled
  name: worker
  replicas: ${WORKERS}
controlPlane:
  hyperthreading: Disabled
  name: master
  replicas: ${MASTERS}
metadata:
  name: ${cluster_name}
networking:
  clusterNetworks:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
pullSecret: '{"auths":{"cloud.openshift.com":{"auth":"b3BlbnNoaWZ0LXJlbGVhc2UtZGV2K29jbV9hY2Nlc3NfMmQ2NmVjYWE0YmU0NGJlNGJmZThiNDYyODBjMTAxZDc6TDVBN0JST0laVDNWSlpHOUwyMTIwNEpENTFZWTVERjkxUjhGNDRJQk1VME1IRlpFR0FQUURCSE5aMUlESE5CUA==","email":"rmr@silicom.dk"},"quay.io":{"auth":"b3BlbnNoaWZ0LXJlbGVhc2UtZGV2K29jbV9hY2Nlc3NfMmQ2NmVjYWE0YmU0NGJlNGJmZThiNDYyODBjMTAxZDc6TDVBN0JST0laVDNWSlpHOUwyMTIwNEpENTFZWTVERjkxUjhGNDRJQk1VME1IRlpFR0FQUURCSE5aMUlESE5CUA==","email":"rmr@silicom.dk"},"registry.connect.redhat.com":{"auth":"fHVoYy1wb29sLTkwMGVkODM4LTZkZWMtNDhiNS04N2FiLTE2N2I2MTdmYWY5MDpleUpoYkdjaU9pSlNVelV4TWlKOS5leUp6ZFdJaU9pSmhOemxrTjJNeU5HTmpZMlkwWXpFNE9XUTJNVGd3WWpGalptWmpNVEE0TmlKOS5iOERUSEJuczZlQnF0ZUhfTlpta2lOcVZCcnJIRXI2ZFRia2tydzFDOTFOMUJrNHVBTGhnRTE0eE1Qd25FaXJkNWtwVXhtOFEtZlJMTERxR241amgtQVRXRlFlZmFMYy1kT25CX0hIdm5qVEZtQ3BreFVPT0hiVmI4X3FNdENIb0VOemFHc09ReEcxaG5RY0VKaXlyaXdmTUVKWk5KbGFFZExwX1I0YmlERDQ5NlhMMTNVRHlnUWpQZWZZVnBRR2xNXzlIT3VXWDVWazNtWW9zUFBROXd1cndGRjZXYjMtM1J1RGtLV0lrMVZpWWhPclpSTkZTNmJ5UWZCUjZqTVBNd2Rhc0ZmRmRnRWwwVDQ2Uk5ZaGpwMktxYVA1MDNwUHltT1dtT2NNTE5lTzJXWHc2V3VQRzZrTEphbHVkV1pUTTNabHNpTTNOc1JSZFdnblZHQmlaWWNMODBsNUVBLUUzeVBJRFlaSk1yZ0xJMkJkSXc1R2ZfT3ctaFZXY2FxczVhTVlaTC1CcmdKNG5pTVhYd2VpZFVKTlJaUjFobHBrM1JGM0hSZkU5MGNCc3FOSW5FZXM3N244VVJKX2lFZUxLc3dJQUxGU1JZWjdYWDhwWG9mU2ZyVEVkV0ZBMGY2Nk92WHRqWFIzMTdrSU9TOGx2RlduZE5iYUJPZVJQaDhibndackotWXFOdG5iMzduNkZ0TXdjUzBfVVotUjZjcGNnUUpmSjNmaG50ZTVnckR3RkpXYTh1eXRRcEFpMWt5bmhFQ2ktWGFiLVlRQ2hJTHFhdGN5Yk1SUXdzYTVfd0tBSmNaQkJHQzNrVThFeTBSVW5pUmY0aXBLLW1jaERHNjl1cXFwQ1JMS1B3SmVySm1SVE5EbUdFYnZfS3B6eGhxckVQbENXbV9TUUVkUQ==","email":"rmr@silicom.dk"},"registry.redhat.io":{"auth":"fHVoYy1wb29sLTkwMGVkODM4LTZkZWMtNDhiNS04N2FiLTE2N2I2MTdmYWY5MDpleUpoYkdjaU9pSlNVelV4TWlKOS5leUp6ZFdJaU9pSmhOemxrTjJNeU5HTmpZMlkwWXpFNE9XUTJNVGd3WWpGalptWmpNVEE0TmlKOS5iOERUSEJuczZlQnF0ZUhfTlpta2lOcVZCcnJIRXI2ZFRia2tydzFDOTFOMUJrNHVBTGhnRTE0eE1Qd25FaXJkNWtwVXhtOFEtZlJMTERxR241amgtQVRXRlFlZmFMYy1kT25CX0hIdm5qVEZtQ3BreFVPT0hiVmI4X3FNdENIb0VOemFHc09ReEcxaG5RY0VKaXlyaXdmTUVKWk5KbGFFZExwX1I0YmlERDQ5NlhMMTNVRHlnUWpQZWZZVnBRR2xNXzlIT3VXWDVWazNtWW9zUFBROXd1cndGRjZXYjMtM1J1RGtLV0lrMVZpWWhPclpSTkZTNmJ5UWZCUjZqTVBNd2Rhc0ZmRmRnRWwwVDQ2Uk5ZaGpwMktxYVA1MDNwUHltT1dtT2NNTE5lTzJXWHc2V3VQRzZrTEphbHVkV1pUTTNabHNpTTNOc1JSZFdnblZHQmlaWWNMODBsNUVBLUUzeVBJRFlaSk1yZ0xJMkJkSXc1R2ZfT3ctaFZXY2FxczVhTVlaTC1CcmdKNG5pTVhYd2VpZFVKTlJaUjFobHBrM1JGM0hSZkU5MGNCc3FOSW5FZXM3N244VVJKX2lFZUxLc3dJQUxGU1JZWjdYWDhwWG9mU2ZyVEVkV0ZBMGY2Nk92WHRqWFIzMTdrSU9TOGx2RlduZE5iYUJPZVJQaDhibndackotWXFOdG5iMzduNkZ0TXdjUzBfVVotUjZjcGNnUUpmSjNmaG50ZTVnckR3RkpXYTh1eXRRcEFpMWt5bmhFQ2ktWGFiLVlRQ2hJTHFhdGN5Yk1SUXdzYTVfd0tBSmNaQkJHQzNrVThFeTBSVW5pUmY0aXBLLW1jaERHNjl1cXFwQ1JMS1B3SmVySm1SVE5EbUdFYnZfS3B6eGhxckVQbENXbV9TUUVkUQ==","email":"rmr@silicom.dk"}}}'
sshKey: '$(cat ${BASE}/node.pub)'
EOF

  # openshift-install create manifests --dir=install
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
  qemu-img create -f raw ${BASE}/${1}.raw ${DISK_GB}G
  chmod a+wr ${1}.raw

  virt-install --connect="qemu:///system" --name="${1}" --vcpus="${VCPUS}" --memory="${2}" \
          --virt-type kvm --accelerate \
          --network network=default,mac="$(virsh net-dumpxml default | grep $hostname | grep mac | sed "s/ name=.*//g" | sed -n "s/.*mac='\(.*\)'/\1/p")" \
          --graphics=none  --noautoconsole --noreboot \
          --disk=${BASE}/${hostname}.raw \
          --location=${IMAGE} \
          --extra-args "nomodeset rd.neednet=1 coreos.inst=yes ignition.platform.id=${1} console=ttyS0 coreos.inst.install_dev=/dev/sda coreos.inst=yes coreos.live.rootfs_url=${rootfs_url} coreos.inst.ignition_url=${ignition_url}/${3} coreos.inst.image_url=${image_url}"
}

cleanup
start_fileserver
create_vm "lb" "4096" "lb.ign"
create_vm "bootstrap" "8192" "bootstrap.ign"

for i in $(seq 1 $MASTERS) ; do
    create_vm "master-$i" "8192" "master.ign"
done

for i in $(seq 1 $WORKERS) ; do
    create_vm "worker-$i" "8192" "worker.ign"
done

sleep 15

while [ ! -z "$(virsh list --state-running --name)" ] ; do
  echo "waiting"
  sleep 20;
done

virsh start "bootstrap"
virsh start "lb"

for i in $(seq 1 $MASTERS) ; do
    virsh start "master-$i"
done

for i in $(seq 1 $WORKERS) ; do
    virsh start "worker-$i"
done

sleep 30

KUBECONFIG=$(pwd)/auth/kubeconfig

$INSTALLER --dir=install_dir wait-for bootstrap-complete --log-level debug

virsh destroy bootstrap
virsh undefine bootstrap --remove-all-storage

$OC get csr -ojson | jq -r '.items[] | select(.status == {} ) | .metadata.name' | xargs --no-run-if-empty $OC adm certificate approve

$INSTALLER --dir=install_dir wait-for install-complete --log-level debug
