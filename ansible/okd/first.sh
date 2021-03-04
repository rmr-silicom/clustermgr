#!/bin/bash

#
# https://kxr.me/2019/08/17/openshift-4-upi-install-libvirt-kvm/
#

set -xe

BASE=$(dirname $(realpath "${BASH_SOURCE[0]}"))

WEB_PORT=8080
HOST_IP=$(ip a | grep -m 1 10.100 | awk '{print $2}' | sed 's/\/.*//')
ignition_url=http://${HOST_IP}:${WEB_PORT}
export cluster_name="openshift"
export BASE_DOM="silicom.local"
VCPUS="2"
RAM_MB="8192"
BOOTSTRAP_RAM_MB="8192"
DISK_GB="10"
install_dir=$BASE/install_dir
IGNITION_CONFIG="/var/lib/libvirt/ignition/fcos-config.ign"
fedora_base="https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/33.20210201.3.0/x86_64/fedora-coreos-33.20210201.3.0"
image_url=${fedora_base}-metal.x86_64.raw.xz
rootfs_url=${fedora_base}-live-rootfs.x86_64.img
VMS="3"

#podman run --pull=always -i --rm -v $BASE:/data -w /data  \
#            quay.io/coreos/coreos-installer:release download -s stable -p qemu -f qcow2.xz --decompress

IMAGE="$(ls $BASE/fedora-coreos-*live*.iso)"

podman run --pull=always -i --rm quay.io/coreos/fcct -p -s <$BASE/fcos-config.fcc > $BASE/fcos-config.ign

[ -e ${install_dir} ] && rm -rf ${install_dir}
mkdir -p ${install_dir}

cat <<EOF > ${install_dir}/install-config.yaml
apiVersion: v1
baseDomain: ${BASE_DOM}
compute:
- hyperthreading: Disabled
  name: worker
  replicas: 0
controlPlane:
  hyperthreading: Disabled
  name: master
  replicas: 3
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
openshift-install create ignition-configs --dir=${install_dir}

if $(docker ps | grep "static-file-server" > /dev/null 2>&1) ; then
    docker rm -f static-file-server
fi

docker run -d --name static-file-server --rm  -v ${install_dir}:/web -p ${WEB_PORT}:${WEB_PORT} -u $(id -u):$(id -g) halverneus/static-file-server:latest
sleep 1
curl ${HOST_IP}:8080/master.ign -s > /dev/null

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

for i in $(seq 0 $VMS) ; do

    RAM=$RAM_MB

    if [ $i -eq 0 ] ; then
      ignition_file=bootstrap.ign
      hostname="bootstrap"
      RAM=$BOOTSTRAP_RAM_MB
    elif [ $i -lt 4 ] ; then
      ignition_file=master.ign
      hostname="master-${i}"
    else
      ignition_file=worker.ign
      hostname="worker-${i}"
    fi

    qemu-img create -f raw ${BASE}/${hostname}.raw ${DISK_GB}G
    chmod a+wr ${hostname}.raw

    virt-install --connect="qemu:///system" --name="${hostname}" --vcpus="${VCPUS}" --memory="${RAM}" \
            --virt-type kvm --accelerate \
            --graphics=none  --noautoconsole --noreboot \
            --disk=${BASE}/${hostname}.raw \
            --location=${IMAGE} \
            --extra-args "nomodeset rd.neednet=1 coreos.inst=yes ignition.platform.id=${hostname} console=ttyS0 coreos.inst.install_dev=/dev/sda coreos.inst=yes coreos.live.rootfs_url=${rootfs_url} coreos.inst.ignition_url=${ignition_url}/${ignition_file} coreos.inst.image_url=${image_url}"
done

sleep 10;

for i in $(seq 0 $VMS) ; do
    if [ $i -eq 0 ] ; then
      hostname="bootstrap"
    elif [ $i -lt 4 ] ; then
      hostname="master-${i}"
    else
      hostname="worker-${i}"
    fi

    mac=$(virsh domifaddr ${hostname} | grep ipv4 | head -n1 | awk '{print $2}')
    ip=$(virsh domifaddr ${hostname} | grep ipv4 | head -n1 | awk '{print $4}' | cut -d'/' -f1 2> /dev/null)

    if [ $hostname = 'bootstrap' ] ; then
      virsh net-update default add-last ip-dhcp-host --xml "<host mac='$mac' name='api-int.${cluster_name}.${BASE_DOM}' ip='$ip'/>" --live --config
      virsh net-update default add-last dns-host --xml "<host ip='$ip'><hostname>api-int.${cluster_name}.${BASE_DOM}</hostname><hostname>bootstrap.${cluster_name}.${BASE_DOM}</hostname><hostname>api.${cluster_name}.${BASE_DOM}</hostname></host>" --live --config
    else
      virsh net-update default add-last ip-dhcp-host --xml "<host mac='$mac' name='$hostname' ip='$ip'/>" --live --config
      virsh net-update default add-last dns-host --xml "<host ip='$ip'><hostname>$hostname.${cluster_name}.${BASE_DOM}</hostname></host>" --live --config
    fi
done

while $(virsh list --all | grep -q running); do
  echo "waiting"
  sleep 20;
done

for i in $(seq 0 $VMS) ; do
    if [ $i -eq 0 ] ; then
      hostname="bootstrap"
    elif [ $i -lt 4 ] ; then
      hostname="master-${i}"
    else
      hostname="worker-${i}"
    fi

    virsh start $hostname
done

sleep 30

./bin/openshift-install --dir=install_dir wait-for bootstrap-complete

./bin/openshift-install --dir=install_dir wait-for install-complete