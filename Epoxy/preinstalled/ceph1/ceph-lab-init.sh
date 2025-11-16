#!/bin/bash

# Epoxy/preinstalled/controller1/ceph-lab-init.sh
set -e
set -x

# Install Ceph packages
sudo apt -y install cephadm ceph-common
# Verify cephadm
cephadm version
# Bootstrap Ceph cluster
sudo cephadm bootstrap --mon-ip 10.20.20.31 --initial-dashboard-user admin --initial-dashboard-password openstack

# Configure Ceph
sudo cephadm shell -- ceph orch host add ceph1 10.20.20.31
sudo cephadm shell -- ceph orch apply osd --all-available-devices

# Allow pools with size=1 on this cluster
sudo cephadm shell -- ceph config set global mon_allow_pool_size_one true

# Set global defaults for new pools (optional but nice)
sudo cephadm shell -- ceph config set global osd_pool_default_size 1
sudo cephadm shell -- ceph config set global osd_pool_default_min_size 1

sudo cephadm shell -- ceph osd pool create images 8
sudo cephadm shell -- ceph osd pool create volumes 8
sudo cephadm shell -- ceph osd pool create backups 8
sudo cephadm shell -- ceph osd pool create vms 8
for p in images volumes backups vms; do
    sudo cephadm shell -- ceph osd pool set "$p" min_size 1
    sudo cephadm shell -- ceph osd pool set "$p" size 1 --yes-i-really-mean-it
    sudo cephadm shell -- ceph osd pool application enable $p rbd 
done
sudo cephadm shell -- ceph health mute POOL_NO_REDUNDANCY

# Create CephX user and export keyrings

mkdir -p ~/ceph-export

sudo cephadm shell -- ceph config generate-minimal-conf > ~/ceph-export/ceph.conf
sudo cephadm shell -- ceph auth get-or-create client.glance mon 'profile rbd' osd 'profile rbd pool=images' > ~/ceph-export/ceph.client.glance.keyring
sudo cephadm shell -- ceph auth get-or-create client.cinder mon 'profile rbd' osd 'profile rbd pool=volumes, profile rbd pool=backups' > ~/ceph-export/ceph.client.cinder.keyring
sudo cephadm shell -- ceph auth get-or-create client.cinder-backup mon 'profile rbd' osd 'profile rbd pool=backups' > ~/ceph-export/ceph.client.cinder-backup.keyring
sudo cephadm shell -- ceph auth get-or-create client.nova mon 'profile rbd' osd 'profile rbd pool=vms' > ~/ceph-export/ceph.client.nova.keyring

cat << EOF 
*******************************************************************************
*                                                                             *
* Power off the VM. Create a snapshot named 'Ceph installed and configured'   *
* Power back on, continue deployment on `controller`                          *
*                                                                             *
*******************************************************************************
EOF