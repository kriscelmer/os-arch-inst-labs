#!/bin/bash

# Epoxy/preinstalled/controller1/post-deploy-validate.sh
# Execute the lines below in after 'deploy-openstack.sh' completes:
# wget -O post-deploy-validate.sh "https://raw.githubusercontent.com/kriscelmer/os-arch-inst-labs/refs/heads/main/Epoxy/preinstalled/controller1/post-deploy-validate.sh"
# bash post-deploy-validate.sh

set -e
set -x


export OS_CLIENT_CONFIG_FILE=/etc/kolla/clouds.yaml
export OS_CLOUD=kolla-admin

# Test basic deployment
openstack token issue
openstack project list
openstack service list

# Test Glance
openstack image list

# Test Nova (with ephemeral disk)
openstack server create demo-vm --flavor m1.tiny --image cirros --key-name demo-key --network demo-net --security-group ssh-icmp

# Test Floating IP assignement
FIP=$(openstack floating ip create public -f value -c floating_ip_address)
openstack server add floating ip demo-vm $FIP

# Test Cinder
openstack volume type create ceph-volume-type
openstack volume type set ceph-volume-type --property volume_backend_name=rbd1

# Test Nova Boot-from-volume
openstack volume create --size 1 --type ceph-volume-type --image cirros boot-vol
openstack server create vm-from-volume --flavor m1.tiny --volume boot-vol --network demo-net --key-name demo-key --security-group ssh-icmp