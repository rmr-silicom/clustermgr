#!/bin/bash

#
# https://kxr.me/2019/08/17/openshift-4-upi-install-libvirt-kvm/
#


#
# https://getfedora.org/en/coreos/download?tab=metal_virtualized&stream=stable
#

set -x

BASE=$(dirname $(realpath "${BASH_SOURCE[0]}"))
WEB_PORT=8080
HOST_IP=$(ip a | grep -m 1 10.100 | awk '{print $2}' | sed 's/\/.*//')
ignition_url=http://${HOST_IP}:${WEB_PORT}
cluster_name="openshift"
base_domain="local"
VCPUS="4"
RAM_MB="8196"
DISK_GB="20"
openshift_ver="4.7.0-0.okd-2021-03-07-090821"
# openshift_ver="4.6.0-0.okd-2021-02-14-205305"
install_dir=$BASE/install_dir
fcos_base="https://builds.coreos.fedoraproject.org/prod/streams/stable/builds"
fcos_ver="33.20210217.3.0"
fedora_base="${fcos_base}/${fcos_ver}/x86_64/fedora-coreos-${fcos_ver}"
image_url=${fedora_base}-metal.x86_64.raw.xz
rootfs_url=${fedora_base}-live-rootfs.x86_64.img
WORKERS="0"
MASTERS="3"
IMAGE="$BASE/fedora-coreos-${fcos_ver}-live.x86_64.iso"
ssh_opts="-i $BASE/../files/node -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
INSTALLER=$BASE/bin/openshift-install
OC=$BASE/bin/oc
export KUBECONFIG=${install_dir}/auth/kubeconfig
disk_type="raw"
DESTROY="no"

# Process Arguments
while [[ $# -gt 0 ]] ; do
  case $1 in
      -m|--masters)
      MASTERS="$2"
      shift
      shift
      ;;
      -w|--workers)
      WORKERS="$2"
      shift
      shift
      ;;
      -r|--ram)
      RAM_MB="$2"
      shift
      shift
      ;;
      -d|--disk)
      DISK_GB="$2"
      shift
      shift
      ;;
      --destroy)
      DESTROY="yes"
      shift
      ;;
      *)
      shift
      ;;
  esac
done

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

  [ ! -e $BASE/rootfs.img ] && wget "${fcos_base}/${fcos_ver}/x86_64/fedora-coreos-${fcos_ver}-live-rootfs.x86_64.img" -O $BASE/rootfs.img
  [ ! -e $BASE/kernel.img ] && wget "${fcos_base}/${fcos_ver}/x86_64/fedora-coreos-${fcos_ver}-live-kernel-x86_64" -O $BASE/kernel.img
  [ ! -e $BASE/initramfs.img ] && wget "${fcos_base}/${fcos_ver}/x86_64/fedora-coreos-${fcos_ver}-live-initramfs.x86_64.img" -O $BASE/initramfs.img

  if [ ! -e $IMAGE ] ; then
#    podman run --privileged --pull=always --rm -v $BASE:/data -w /data \
#        quay.io/coreos/coreos-installer:release download -s stable -p metal -f iso
#   isoinfo -J -i /home/rmr/kubernetes/kubernetes-operator/ansible/okd/fedora-coreos-33.20210217.3.0-live.x86_64.iso -f
    wget https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${fcos_ver}/x86_64/fedora-coreos-${fcos_ver}-live.x86_64.iso -O ${IMAGE}
  fi

  [ ! -e $BASE/bin ] && mkdir -p $BASE/bin

  if [ ! -e ${INSTALLER} ] || [ ${INSTALLER} version | grep -q ${openshift_ver} ] ; then
    wget https://github.com/openshift/okd/releases/download/${openshift_ver}/openshift-install-linux-${openshift_ver}.tar.gz
    tar xvf openshift-install-linux-${openshift_ver}.tar.gz -C $BASE/bin/
    chmod +x  ${INSTALLER}
  fi

  if [ ! -e ${OC} ] || [ ${OC} version | grep -q ${openshift_ver} ] ; then
    wget https://github.com/openshift/okd/releases/download/${openshift_ver}/openshift-client-linux-${openshift_ver}.tar.gz
    tar xvf openshift-client-linux-${openshift_ver}.tar.gz -C $BASE/bin/
    chmod +x  ${OC}
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
pullSecret: '$(cat ${BASE}/../files/pull-secret.json)'
sshKey: '$(cat ${BASE}/../files/node.pub)'
EOF

  cp $BASE/../files/lb.fcc $BASE/lb.fcc
  $INSTALLER create manifests --dir=${install_dir}
  if [ "$WORKERS" = "0" ] ; then
    sed -i 's/mastersSchedulable: false/mastersSchedulable: true/g' ${install_dir}/manifests/cluster-scheduler-02-config.yml
    sed -i 's/worker1 worker1.openshift.local/master1 master1.openshift.local/g' $BASE/lb.fcc
    sed -i 's/worker2 worker2.openshift.local/master2 master2.openshift.local/g' $BASE/lb.fcc
    sed -i 's/worker3 worker3.openshift.local/master3 master3.openshift.local/g' $BASE/lb.fcc
  else
    sed -i 's/mastersSchedulable: true/mastersSchedulable: false/g' ${install_dir}/manifests/cluster-scheduler-02-config.yml
  fi

  if [ "$WORKERS" = "2" ] ; then
    sed -i '/worker3 worker3.openshift.local/d' $BASE/lb.fcc
  fi

  $INSTALLER create ignition-configs --dir=${install_dir}

  podman run --pull=always -i --rm quay.io/coreos/fcct -p -s <$BASE/lb.fcc > ${install_dir}/lb.ign

  while $(virsh list --state-running | grep -q running); do
    virsh destroy $(virsh list --state-running --name | head -n1)
  done

  while [ ! -z "$(virsh list --all --name)" ] ; do
    virsh undefine $(virsh list --all --name | head -n1) --remove-all-storage
  done

  while [ ! -z "$(ls ${BASE}/*.$disk_type)" ] ; do
    rm -f $(ls ${BASE}/*.$disk_type | head -n1)
  done

  if $(virsh net-list | grep -q default); then
    virsh net-destroy default
    virsh net-undefine default
  fi

  virsh net-define --file ${BASE}/../files/default.xml
  virsh net-start default
}

create_vm() {
  local hostname=$1
  local disk=${BASE}/${hostname}.$disk_type

  qemu-img create -f $disk_type ${disk} ${DISK_GB}G
  chmod a+wr ${disk}

  device="$(lspci -d 1c2c:1000 | awk '{ print $1 }')"
  lspci_args=""
  if [ $hostname = "worker1" ] ; then
    if [ ! -z "$device" ] ; then
      lspci_args="--hostdev $device"
    else
      lspci_args="--hostdev $(lspci -d 10ec:525a | awk '{ print $1 }')"
    fi
  fi

  virt-install --connect="qemu:///system" --name="${1}" --vcpus="${VCPUS}" --memory="${2}" \
          --virt-type kvm \
          --accelerate \
          --hvm $lspci_args \
          --os-variant rhl9 \
          --network network=default,mac="$(virsh net-dumpxml default | grep $hostname | grep mac | sed "s/ name=.*//g" | sed -n "s/.*mac='\(.*\)'/\1/p")" \
          --graphics=none \
          --noautoconsole \
          --noreboot \
          --disk=${disk} \
          --install kernel=$BASE/kernel.img,initrd=$BASE/initramfs.img \
          --extra-args "coreos.inst=yes console=ttyS0 coreos.inst.install_dev=/dev/sda coreos.live.rootfs_url=${rootfs_url} coreos.inst.ignition_url=${ignition_url}/${3} coreos.inst.image_url=${image_url}"
}

cleanup

if [ $DESTROY = "yes" ] ; then
  exit 0
fi

start_fileserver
create_vm "lb" "2048" "lb.ign"
create_vm "bootstrap" "8196" "bootstrap.ign"

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

for i in $(seq 1 $MASTERS) ; do
    virsh start "master$i"
done

virsh start "bootstrap"
while ! $(nc -v -z -w 1 lb.openshift.local 6443 > /dev/null 2>&1); do
  echo "Waiting for bootstrap"
  sleep 30
done


for i in $(seq 1 $WORKERS) ; do
    virsh start "worker$i"
done

while ! $(nc -v -z -w 1 master$MASTERS.openshift.local 22 > /dev/null 2>&1); do
  echo "Waiting for master$MASTERS"
  sleep 30
done
date

while ! $(ssh ${ssh_opts} core@bootstrap.${cluster_name}.${base_domain} "[ -e /opt/openshift/cco-bootstrap.done ]") ; do
  echo -n "Waiting for cco-bootstrap.done"
  sleep 30
done
date

$INSTALLER --dir=${install_dir} wait-for bootstrap-complete --log-level debug

while ! $(ssh ${ssh_opts} core@bootstrap.${cluster_name}.${base_domain} "[ -e /opt/openshift/cb-bootstrap.done ]") ; do
  echo -n "Waiting for cb-bootstrap.done"
  sleep 30
done
date

while ! $(ssh ${ssh_opts} core@bootstrap.${cluster_name}.${base_domain} "[ -e /opt/openshift/.bootkube.done ]") ; do
  echo -n "Waiting for .bootkube.done"
  sleep 30
done
date

$INSTALLER gather bootstrap --dir=${install_dir}

virsh destroy bootstrap
virsh undefine bootstrap --remove-all-storage

virsh destory lb
sed -i '/bootstrap/d' $BASE/lb.fcc
virsh start "lb"
while ! $(nc -v -z -w 1 lb.openshift.local 22 > /dev/null 2>&1); do
  echo "Waiting for lb"
  sleep 30
done


sleep 300
$OC get csr -ojson | jq -r '.items[] | select(.status == {} ) | .metadata.name' | xargs --no-run-if-empty $OC adm certificate approve
$OC get csr -o name | xargs oc adm certificate approve

$INSTALLER --dir=${install_dir} wait-for install-complete --log-level debug

$OC apply -f ${BASE}/../files/silicom-registry.yaml
$OC apply -f ${BASE}/../files/nfd-daemonset.yaml
