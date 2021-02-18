#!/bin/sh

set -xe

export HOME=/root
export KUBECONFIG=/etc/kubernetes/admin.conf
export no_proxy=$no_proxy,.svc,.svc.cluster.local

cat > /etc/hosts <<EOF
127.0.0.1	localhost $(hostname)

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

while ! $(ping -q -c 1 -W 5 8.8.8.8 > /dev/null 2>&1); do
    logger 'No network'
    sleep 1;    
done

while ! $(kubeadm init --v=5 > /tmp/kubeadm.log 2>&1); do
    kubeadm reset -f
    logger 'Init failed'
    sleep 5;    
done

mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config
chown $(id -u):$(id -g) /root/.kube/config

kubectl version -o json
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
# kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
kubectl apply -f "https://github.com/jetstack/cert-manager/releases/download/v1.0.3/cert-manager.yaml"
kubectl annotate node g9-centos-8-2-master 'fpga.intel.com/device-plugin-mode=region'
kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.1.0/aio/deploy/recommended.yaml
kubectl create serviceaccount dashboard-admin-sa
kubectl create clusterrolebinding dashboard-admin-sa --clusterrole=cluster-admin --serviceaccount=default:dashboard-admin-sa

# kubectl get secrets
# kubectl describe secret dashboard-admin-sa-token-kw7vn

#
# https://upcloud.com/community/tutorials/deploy-kubernetes-dashboard/
#
# https://schoolofdevops.github.io/ultimate-kubernetes-bootcamp/helm/
#
# kubectl create serviceaccount --namespace kube-system tiller
# kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller

kubectl taint nodes --all node-role.kubernetes.io/master-

while ! $(kubectl get pods --all-namespaces | grep -q coredns | grep Running); do
    sleep 1;
    logger "Wating for coredns before adding nodes."
done

while ! $(kubectl get nodes | grep -q Ready); do
    sleep 1;
    logger "Waiting for kubctl"
done

cat > /join.sh << EOF
#!/bin/bash

set -xe

export HOME=/root
export KUBECONFIG=/etc/kubernetes/admin.conf

while ! $(ping -q -c 1 -W 5 8.8.8.8 > /dev/null 2>&1); do
    logger 'No network'
    sleep 1;    
done

systemctl enable kubelet.service

$(kubeadm token create --print-join-command) --v=5

mkdir -p /root/.kube
cp -i /etc/kubernetes/kubelet.conf /root/.kube/config
    
EOF
sync -f

systemctl enable kubelet
