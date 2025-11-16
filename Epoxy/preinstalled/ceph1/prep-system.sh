#!/bin/bash

# Epoxy/preinstalled/ceph1/prep-system.sh
set -e
set -x

# Convenience: passwordless sudo for openstack user
echo 'openstack ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/90-openstack

cat <<'YAML' | sudo tee /etc/netplan/01-netcfg.yaml >/dev/null 
network:
  version: 2
  renderer: networkd
  ethernets:
    ens32: {dhcp4: true}                 # NAT egress
    ens33: {addresses: [10.0.0.31/24], nameservers: {addresses: [10.0.0.1]}}
    ens34: {addresses: [10.20.20.31/24]} # Ceph public/cluster for this lab
YAML
sudo chmod 600 /etc/netplan/01-netcfg.yaml
sudo netplan apply

sudo apt-get update -y
sudo apt -y install chrony git curl jq vim python3-venv python3-pip net-tools lvm2 bash-completion ca-certificates gnupg
echo "makestep 1.0 -1" | sudo tee -a /etc/chrony/chrony.conf
sudo systemctl enable --now chrony
sudo chronyc makestep
sudo systemctl restart chrony

# Disable swap (Kolla prechecks require it)
sudo swapoff -a
sudo sed -ri '/\sswap\s/ s/^/#/' /etc/fstab

# Make sure management hostnames resolve everywhere
echo '10.0.0.11 controller1
10.0.0.21 compute1
10.0.0.22 compute2
10.0.0.31 ceph1' | sudo tee -a /etc/hosts

echo "Waiting for controller1 to install SSH public key."
read -p "Hit Enter when installed..." GO

cat << 'EOF'
*******************************************************************************
*                                                                             *
* Power off the VM. Create a snapshot named 'System installed and configured' *
* Power back on, continue deployment on `controller`                          *
*                                                                             *
*******************************************************************************
EOF