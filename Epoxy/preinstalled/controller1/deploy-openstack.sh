#!/bin/bash

# Epoxy/preinstalled/controller1/deploy-openstack.sh
# Execute the lines below in a freshly installed VM:
# wget -O deploy-openstack.sh "https://raw.githubusercontent.com/kriscelmer/os-arch-inst-labs/refs/heads/main/Epoxy/preinstalled/controller1/deploy-openstack.sh"
# bash deploy-openstack.sh

set -e
set -x

INVENTORY_FILE="./inventory"

# Create base globals.yaml
cat << 'EOF' > /etc/kolla/globals.yml
# /etc/kolla/globals.yml
kolla_base_distro: "ubuntu"
openstack_release: "2025.1"

network_interface: "ens33"
api_interface: "{{ network_interface }}"
tunnel_interface: "ens34"
storage_interface: "ens35"
dns_interface: "{{ network_interface }}"
neutron_external_interface: "ens36"

kolla_internal_vip_address: "10.0.0.11"
kolla_external_vip_address: "10.0.0.11"

# We plan OVN later, so set the plugin now
neutron_plugin_agent: "ovn"
EOF

mkdir -p /etc/kolla/globals.d

# Create globals for Infra
cat << 'EOF' > /etc/kolla/globals.d/00-core.yml
# Infra + Keystone only
enable_mariadb: "yes"
enable_rabbitmq: "yes"
enable_memcached: "yes"
enable_haproxy: "no"
enable_keepalived: "no"
enable_mariadb_proxy: "no"
enable_proxysql: "no"
enable_rabbitmq_cluster: "no"

enable_keystone: "yes"

# Disable services for now
enable_designate: "no"
EOF

# Create globals for Glance with file backend and Horizon
cat << 'EOF' > /etc/kolla/globals.d/10-glance-horizon.yml
enable_glance: "yes"

# Start with simple file backend; we’ll switch to Ceph later
glance_backend_file: "yes"
glance_backend_ceph: "no"
EOF

# Create globals for Neutron (OVN) and Nova
cat << 'EOF' > /etc/kolla/globals.d/20-neutron-nova.yml
enable_neutron: "yes"

neutron_plugin_agent: "ovn"    # already set in globals, but okay to repeat
enable_ovn: "{{ enable_neutron | bool }}"

# For a small lab you can keep these “no”
neutron_ovn_distributed_fip: "no"
neutron_ovn_dhcp_agent: "no"
neutron_enable_ovn_agent: "no"

enable_nova: "yes"
enable_placement: "yes"        # placement is needed when nova is enabled
# Keep local storage for now
nova_backend_ceph: "no"
EOF

# Enable Cinder and Ceph backend for Cinder, Nova and Glance

cat << 'EOF' > /etc/kolla/globals.d/30-ceph.yml
enable_cinder: "yes"
enable_cinder_backup: "yes"

# Enable Ceph backends
cinder_backend_ceph: "yes"
cinder_backup_driver: "ceph"

glance_backend_ceph: "yes"
glance_backend_file: "no"

nova_backend_ceph: "yes"

# External Ceph auth
external_ceph_cephx_enabled: "yes"

# Pool/user mapping (match what you set in Ceph)
ceph_glance_user: "glance"
ceph_glance_pool_name: "images"

ceph_cinder_user: "cinder"
ceph_cinder_pool_name: "volumes"
ceph_cinder_backup_user: "cinder-backup"
ceph_cinder_backup_pool_name: "backups"

ceph_nova_user: "nova"
ceph_nova_pool_name: "vms"

# Align client packages with your Ceph cluster version
ceph_version: "squid"   # or pacific/quincy/etc
EOF

# Enable dashboards
cat << 'EOF' > /etc/kolla/globals.d/40-dashboards.yml
enable_horizon: "yes"          # already enabled, but fine
enable_skyline: "yes"

# Optional: disable SSO in Skyline to keep it simple
skyline_enable_sso: "no"
EOF

# Copy Ceph config files and keyrings
mkdir -p /etc/kolla/config/glance
mkdir -p /etc/kolla/config/cinder
mkdir -p /etc/kolla/config/cinder/cinder-volume
mkdir -p /etc/kolla/config/cinder/cinder-backup
mkdir -p /etc/kolla/config/nova

cp ~/ceph-artifacts/ceph.conf /etc/kolla/config/glance/ceph.conf
cp ~/ceph-artifacts/ceph.conf /etc/kolla/config/cinder/ceph.conf
cp ~/ceph-artifacts/ceph.conf /etc/kolla/config/nova/ceph.conf
cp ~/ceph-artifacts/ceph.client.glance.keyring /etc/kolla/config/glance/ceph.client.glance.keyring
cp ~/ceph-artifacts/ceph.client.cinder.keyring /etc/kolla/config/cinder/cinder-volume/ceph.client.cinder.keyring
cp ~/ceph-artifacts/ceph.client.cinder.keyring /etc/kolla/config/cinder/cinder-backup/ceph.client.cinder.keyring
cp ~/ceph-artifacts/ceph.client.cinder-backup.keyring /etc/kolla/config/cinder/cinder-backup/ceph.client.cinder-backup.keyring
cp ~/ceph-artifacts/ceph.client.nova.keyring /etc/kolla/config/nova/ceph.client.nova.keyring
cp ~/ceph-artifacts/ceph.client.cinder.keyring /etc/kolla/config/nova/ceph.client.cinder.keyring

kolla-ansible bootstrap-servers -i $INVENTORY_FILE
kolla-ansible prechecks -i $INVENTORY_FILE

kolla-ansible genconfig -i $INVENTORY_FILE
kolla-ansible validate-config -i $INVENTORY_FILE

kolla-ansible deploy -i $INVENTORY_FILE
kolla-ansible post-deploy -i $INVENTORY_FILE

# Install CLI in the venv
pip install python-openstackclient
export OS_CLIENT_CONFIG_FILE=/etc/kolla/clouds.yaml
export OS_CLOUD=kolla-admin

# Test basic deployment
openstack token issue
openstack project list
openstack service list

# Test Glance
wget -O cirros.qcow2 https://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img
openstack image create cirros --disk-format qcow2 --container-format bare --file cirros.qcow2
openstack image list

# Test networking
# Internal tenant network (Geneve overlay via OVN)
openstack network create demo-net
openstack subnet create demo-subnet --network demo-net --subnet-range 192.168.100.0/24 --dns-nameserver 8.8.8.8

# External provider network mapped to ens4/br-ex
openstack network create public --external --provider-network-type flat --provider-physical-network physnet1

VM_NAT_net_prefix=$(sudo ip -4 -o a show ens32 | awk '{print $4}' | cut -d '.' -f 1,2,3)
openstack subnet create --network public --allocation-pool start=$VM_NAT_net_prefix.100,end=$VM_NAT_net_prefix.127 --gateway $VM_NAT_net_prefix.2 --subnet-range $VM_NAT_net_prefix.0/24 public-subnet

openstack router create demo-router
openstack router set demo-router --external-gateway public
openstack router add subnet demo-router demo-subnet

openstack security group create --description 'Allows ssh and ping from any host' ssh-icmp
openstack security group rule create --ethertype IPv4 --protocol icmp --remote-ip 0.0.0.0/0 ssh-icmp
openstack security group rule create --ethertype IPv4 --protocol tcp --dst-port 22 --remote-ip 0.0.0.0/0 ssh-icmp

openstack flavor create --ram 512 --disk 2 --vcpus 1 m1.tiny
openstack keypair create demo-key > demo-key.pem
chmod 600 demo-key.pem

openstack server create demo-vm --flavor m1.tiny --image cirros --key-name demo-key --network demo-net --security-group ssh-icmp

FIP=$(openstack floating ip create public -f value -c floating_ip_address)
openstack server add floating ip demo-vm $FIP

openstack volume type create ceph-volume-type
openstack volume type set ceph-volume-type --property volume_backend_name=rbd1

openstack volume create --size 1 --type ceph-volume-type --image cirros boot-vol
openstack server create vm-from-volume --flavor m1.tiny --volume boot-vol --network demo-net --key-name demo-key --security-group ssh-icmp

cat << 'EOF'
export OS_CLIENT_CONFIG_FILE=/etc/kolla/clouds.yaml
export OS_CLOUD=kolla-admin
EOF
