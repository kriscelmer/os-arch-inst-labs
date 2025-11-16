#!/bin/bash

# Epoxy/preinstalled/controller1/prep-system.sh
# set -euo pipefail

set -e
set -x

# Convenience: passwordless sudo for openstack user
echo 'openstack ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/90-openstack

cat <<'YAML' | sudo tee /etc/netplan/01-netcfg.yaml >/dev/null 
network:
  version: 2
  renderer: networkd
  ethernets:
    ens32: {dhcp4: true}        # NAT egress
    ens33: {addresses: [10.0.0.11/24], nameservers: {addresses: [10.0.0.1]}, routes: []}
    ens34: {addresses: [10.10.10.11/24]}
    ens35: {addresses: [10.20.20.11/24]}
    ens36: {dhcp4: false, dhcp6: false, optional: true}  # provider, no IP
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

echo "Waiting for ceph1, compute1 and compute2 to become ready to distribute SSH public key."
read -p "Hit Enter when all 3 are ready..." > /dev/null GO

# Generate SSH key pair and copy public key to all nodes
ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
for h in compute1 compute2 ceph1; do
  ssh-copy-id -i ~/.ssh/id_ed25519.pub openstack@$h # for each machine confirm you want to connect and type in the password
done

# Test SSH connectivity
ssh openstack@controller1 'echo "ssh openstack@controller1 works!"' # confirm you want to connect, if asked
ssh openstack@10.0.0.11 'echo "ssh openstack@10.0.0.11 works!"' # confirm you want to connect, if asked
ssh openstack@compute1 'echo "ssh openstack@compute1 works!"'
ssh openstack@10.0.0.21 'echo "ssh openstack@10.0.0.21 works!"' # confirm you want to connect, if asked
ssh openstack@compute2 'echo "ssh openstack@compute2 works!"'
ssh openstack@10.0.0.22 'echo "ssh openstack@10.0.0.22 works!"' # confirm you want to connect, if asked
ssh openstack@ceph1 'echo "ssh openstack@ceph1 works!"'
ssh openstack@10.0.0.31 'echo "ssh openstack@10.0.0.31 works!"' # confirm you want to connect, if asked

echo << 'EOF'
*******************************************************************************
*                                                                             *
* Power off the VM. Create a snapshot named 'System installed and configured' *
* Power back on, wait for other VMs to complete `prep-system.sh` and snapshot *
* and run `bash kolla-bootstrap.sh`.                                          *
*                                                                             *
*******************************************************************************
EOF
