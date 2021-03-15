#!/bin/bash

set +x

# IMPORTANT: Change the "VM NAME" string to match your actual VM Name.
# In order to create rules to other VMs, just duplicate the below block and configure
# it accordingly.
# https://wiki.libvirt.org/page/Networking#NAT_forwarding_.28aka_.22virtual_networks.22.29
#
if [ "${1}" = "lb" ]; then

   # Update the following variables to fit your setup
   GUEST_IP=192.168.122.9
   GUEST_PORT=443
   HOST_PORT=443

   if [ "${2}" = "stopped" ] || [ "${2}" = "reconnect" ]; then
	/usr/sbin/iptables -D FORWARD -o virbr0 -p tcp -d $GUEST_IP --dport $GUEST_PORT -j ACCEPT
	/usr/sbin/iptables -t nat -D PREROUTING -p tcp --dport $HOST_PORT -j DNAT --to $GUEST_IP:$GUEST_PORT
   fi
   if [ "${2}" = "start" ] || [ "${2}" = "reconnect" ]; then
	/usr/sbin/iptables -I FORWARD -o virbr0 -p tcp -d $GUEST_IP --dport $GUEST_PORT -j ACCEPT
	/usr/sbin/iptables -t nat -I PREROUTING -p tcp --dport $HOST_PORT -j DNAT --to $GUEST_IP:$GUEST_PORT
   fi
fi