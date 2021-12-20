#!/bin/bash

#
# Script usage, in /home/umbrel:
#   wget install-umbrel.sh
#   ./install-umbrel.sh
#

set -e

UMBREL_VERSION='0.4.9'

user=`whoami`
if [ $user != 'umbrel' ]; then
  echo 'Error: Expected user `umbrel`, but it was '$user
  exit 1
fi

userId=`id -u`
if [ $userId != 1000 ]; then
  echo 'Error: Expected user id 1000, but it was '$userId
  echo 'This script has to be executed as the first non-administrator (non-root) user.'
  exit 1
fi

##Functions####################################################################

function log() {
  echo -e '\n'$1
}

function installDockerEngine() {
  log 'remove old docker'
  set +e
  sudo apt-get remove \
    containerd \
    docker \
    docker-engine \
    docker.io \
    runc
  set -e

  log 'install docker'
  sudo apt-get install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

  log "add docker's official GPG key"
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg -v --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

  log 'set up the stable repository'
  echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update

  log 'install docker engine'
  sudo apt-get install docker-ce docker-ce-cli containerd.io
}

function manageDockerAsNonRoot() {
  log 'create docker group'
  sudo groupadd -f docker
  user=`whoami`
  sudo usermod -aG docker $user

  log 'configure Docker to start on boot'
  sudo systemctl enable docker.service
  sudo systemctl enable containerd.service
}

function installDockerCompose() {
  log 'install docker compose'
  sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
}

function cpService() {
  fileName=$1
  filePath=/etc/systemd/system/$1

  sudo cp -v ./scripts/umbrel-os/services/$1 $filePath
  
  # don't need these services
  externalStorage='umbrel-external-storage.service'
  externalStorageSd='umbrel-external-storage-sdcard-update.service'

  r='Requires='$externalStorage
  a='After='$externalStorage
  b='Before='$externalStorage
  sudo sed -i "/$r/d" $filePath
  sudo sed -i "/$a/d" $filePath
  sudo sed -i "/$b/d" $filePath

  r='Requires='$externalStorageSd
  a='After='$externalStorageSd
  b='Before='$externalStorageSd
  sudo sed -i "/$r/d" $filePath
  sudo sed -i "/$a/d" $filePath
  sudo sed -i "/$b/d" $filePath
}

function installUmbrel() {
  umbrelFolder=~/umbrel

  log 'Install Umbrel '$UMBREL_VERSION
  mkdir -pv $umbrelFolder
  cd $umbrelFolder
  curl -L 'https://github.com/getumbrel/umbrel/archive/v'$UMBREL_VERSION'.tar.gz' | tar -xz --strip-components=1

  log 'copy services'
  sudo rm -vf /etc/systemd/system/umbrel*
  cpService umbrel-startup.service
  cpService umbrel-connection-details.service
  cpService umbrel-status-server-iptables-update.service
  cpService umbrel-status-server.service

  sudo chmod 644 /etc/systemd/system/umbrel-*

  sudo systemctl enable umbrel-startup.service
  sudo systemctl enable umbrel-connection-details.service
  sudo systemctl enable umbrel-status-server-iptables-update.service
  sudo systemctl enable umbrel-status-server.service
  cd -
}

##Execute######################################################################

log 'install dependencies'
sudo apt update -y
sudo apt-get install fswatch jq rsync curl git

installDockerEngine

manageDockerAsNonRoot

installDockerCompose

log 'verify Docker installation'
newgrp docker << DOCKERPERMISSIONED
  set -e
  docker run hello-world
  exit 0
DOCKERPERMISSIONED

installUmbrel

sudo ./umbrel/scripts/start 

log 'Install completed. If you like, reboot to verify Umbrel starts on bootstrap.'

exit 0

