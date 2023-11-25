#!/bin/bash
# For Ubuntu Server 22.04.02 LTS
# to make file executable run: sudo chmod +x jc_install.sh
# to run the file: sudo ./jc_install.sh

IP=$(hostname -I | cut -f1 -d' ')

# Updating and preapring server
echo "Updating server and preparing install.."
sleep 5
sudo apt-get update
sudo apt-get upgrade -y

# Install some useful tools
echo "Installing Intel GPU tools..."
sudo apt-get install intel-gpu-tools dnsutils htop iputils-ping build-essential -y

# No-ip client
cd /usr/local/src/
wget http://www.noip.com/client/linux/noip-duc-linux.tar.gz
tar xf noip-duc-linux.tar.gz
cd noip-2.1.9-1/
make install

echo "Launching no-ip client...you will now be asked to login..."
sleep 5
sudo /usr/local/bin/noip2 -C

# Write service bash script
sudo tee /etc/init.d/noip2.sh << EOF
#! /bin/sh
# . /etc/rc.d/init.d/functions # uncomment/modify for your killproc
case "$1" in
start)
echo "Starting noip2."
/usr/local/bin/noip2
;;
stop)
echo -n "Shutting down noip2."
killproc -TERM /usr/local/bin/noip2
;;
*)
echo "Usage: $0 {start|stop}"
exit 1
esac
exit 0
EOF

# Write service file.
sudo tee << /etc/systemd/system/noip2.service << EOF
[Unit]
Description=noip2 service

[Service]
Type=forking
ExecStart=/usr/local/bin/noip2
Restart=always

[Install]
WantedBy=default.target
EOF

# Ubuntu server 20.04  Change from netplan to NetworkManager for all interfaces
echo "Changing netplan to NetowrkManager on all interfaces..."
sleep 5
sudo apt-get install network-manager -y

echo 'Changing netplan to NetowrkManager on all interfaces'
# backup existing yaml file
cd /etc/netplan
cp 01-netcfg.yaml 01-netcfg.yaml.BAK

# re-write the yaml file
cat << EOF > /etc/netplan/01-netcfg.yaml
# This file describes the network interfaces available on your system
# For more information, see netplan(5).
network:
  version: 2
  renderer: NetworkManager
EOF

# Download NordVPN installer
#echo "Installing NordVPN..."
#sleep 5
#sudo mkdir /nordvpn
#cd /nordvpn
#wget https://downloads.nordcdn.com/apps/linux/install.sh
#sudo chmod +x install.sh
#sudo ./install.sh

# login in to nordvpn and whitelist local traffic & enable meshnet
#nordvpn login --token "enter token here minus quotes"
#nordvpn whitelist add subnet "enter subnet here in slash notation minus quotes example: 192.168.1.0/24"
#nordvpn set meshnet on

# Install and enable cockpit
sudo apt-get install cockpit -y
sudo systemctl enable --now cockpit.socket

# Add docker repository and install docker
echo "Preparing to install docker..."
sleep 5
echo "Preparing dependencies..."
sleep 5
sudo apt-get install ca-certificates curl gnupg vim -y
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
echo "Installiing docker..."
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
sleep 5
echo "Starting docker services and adding to start up..."
sleep 5
sudo systemctl enable --now docker

# Pull down latest Portainer docker image and launch inside docker.
echo "Preparing to install portainer within docker..."
sleep 5
echo "Creating portainer_data volume..."
sleep 5
sudo docker volume create portainer_data
echo "Launching portainer container..."
sleep 5
docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
sleep 5

# Intall samba
echo "Preparing to install samba..."
sleep 5
sudo apt-get install install samba samba-common samba-client -y
echo "Backing up original config file..."

sudo mv /etc/samba/smb.conf /etc/samba/smb.conf.org
sudo tee /etc/samba/smb.conf <<EOF
[global]
  workgroup = WORKGROUP
  server string = Samba Server Version %v
  netbios name = CENTOS
  security = user
  security = user
  passdb backend = tdbsam
  wins support = yes

[media_sda1]
  path = /media_sda1
  available = yes
  valid users = jcadmin
  readonly = no
  browseable = yes
  public = yes
  writable = yes
  hosts allow = 192.168.1.0/255.255.255.0

[media_sdb2]
  path = /media_sdb2
  available = yes
  valid users = jcadmin
  readonly = no
  browseable = yes
  public = yes
  writable = yes
  hosts allow = 192.168.1.0/255.255.255.0
EOF

# GPU setup
sudo tee /etc/modprobe.d/i915.conf << EOF
options i915 enable_guc=2
EOF

# Opening ports on Ubuntu firewall
echo "Enable firewall and opening required ports..."
sleep 5
sudo ufw enable
sudo ufw allow 22
sudo ufw allow 9443
sudo ufw allow 9090
sudo ufw allow 139
sudo ufw allow 445
sudo ufw allow 32400

echo "INSTALLATION COMPLETE!"
read -p "Portainer can be accessed from https://$IP:9443 and Cockpit from https://$IP:9090 press ENTER exit install!"

# Updated boot img for GPU passthrough
sudo update-initramfs -u
sleep 5

# setup netplan for NM
echo "Generating and applying netplan changes..."
netplan generate
netplan apply

# make sure NM is running
systemctl enable NetworkManager.service
systemctl restart NetworkManager.service
sudo reboot
