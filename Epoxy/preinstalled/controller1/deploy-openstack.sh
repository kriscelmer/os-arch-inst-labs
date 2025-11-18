#!/bin/bash

# Epoxy/preinstalled/controller1/deploy-openstack.sh
set -e
set -x

INVENTORY_FILE="./inventory"

# Create base globals.yaml
cat << 'EOF' > /etc/kolla/globals.yml
# /etc/kolla/globals.yml
kolla_base_distro: "ubuntu"
openstack_release: "2025.1"

network_interface: "ens3"
api_interface: "{{ network_interface }}"
tunnel_interface: "{{ network_interface }}"
storage_interface: "{{ network_interface }}"
dns_interface: "{{ network_interface }}"
neutron_external_interface: "ens4"

kolla_internal_vip_address: "10.0.0.10"
kolla_external_vip_address: "10.0.0.10"

# Disable the “all core services at once” bundle
enable_openstack_core: "no"

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

# Everything else off for now
enable_glance: "no"
enable_neutron: "no"
enable_nova: "no"
enable_cinder: "no"
enable_heat: "no"
enable_designate: "no"
enable_skyline: "no"
EOF

kolla-ansible bootstrap-servers -i $INVENTORY_FILE
kolla-ansible prechecks -i $INVENTORY_FILE

kolla-ansible gencofig -i $INVENTORY_FILE
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
