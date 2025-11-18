#!/bin/bash

# Epoxy/preinstalled/controller1/kolla-bootstrap.sh
set -e
set -x

# Copy Ceph artifacts to controller1
mkdir -p ~/ceph-artifacts
scp openstack@ceph1:ceph-export/ceph.conf ~/ceph-artifacts/
scp openstack@ceph1:ceph-export/ceph.client.{glance,cinder,cinder-backup,nova}.keyring ~/ceph-artifacts/
sed -i -E 's/^[[:space:]]+//' ~/ceph-artifacts/ceph.conf
sed -i -E 's/^[[:space:]]+//' ~/ceph-artifacts/ceph.client.glance.keyring
sed -i -E 's/^[[:space:]]+//' ~/ceph-artifacts/ceph.client.cinder.keyring
sed -i -E 's/^[[:space:]]+//' ~/ceph-artifacts/ceph.client.cinder-backup.keyring
sed -i -E 's/^[[:space:]]+//' ~/ceph-artifacts/ceph.client.nova.keyring

# Install required packages
sudo apt update
sudo apt -y install git python3-dev libffi-dev gcc libssl-dev libdbus-glib-1-dev python3-venv
# (Recommended) dedicated venv on the deployment host
python3 -m venv ~/openstack-venv && source ~/openstack-venv/bin/activate
echo "source ~/openstack-venv/bin/activate" >> ~/.bashrc
pip install -U pip

# Install Kolla Ansible stable/2025.1
pip install "git+https://opendev.org/openstack/kolla-ansible@stable/2025.1"

# Install Galaxy role deps
kolla-ansible install-deps

# Create baseline /etc/kolla and seed example files
sudo mkdir -p /etc/kolla
sudo chown "$USER:$USER" /etc/kolla
cp -r ~/openstack-venv/share/kolla-ansible/etc_examples/kolla/* /etc/kolla
cp ~/openstack-venv/share/kolla-ansible/ansible/inventory/multinode ./inventory

# Generate passwords
kolla-genpwd
# Set "admin"password to "openstack"
sed -i 's/^keystone_admin_password:.*/keystone_admin_password: openstack/' /etc/kolla/passwords.yml