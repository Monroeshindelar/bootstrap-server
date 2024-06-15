#!/bin/bash

IFS=" "
BOOTSTRAP_KUBE_NODE=false
BOOTSTRAP_REBOOT=false
BOOTSTRAP_SKIP_HOSTS=false
HELPERS_PATH="helpers"
SSH_CONFIG_PATH="ssh"
ZSH_CONFIG_PATH="zsh"

print_usage() {
    printf "Usage: ..."
}

sudo apt-get update

chmod +x $HELPERS_PATH/hostsHelper.sh

while getopts 'ghks' flag; do
    case "${flag}" in
        g) 
            BOOTSTRAP_GH_USER=${OPTARG} ;;
        h) 
            BOOTSTRAP_HOSTNAME=${OPTARG} ;;
        k) 
            echo "Is kube node. Will install kubernetes packages"
            BOOTSTRAP_KUBE_NODE=true ;;
        r)
            echo "Rebooting when complete"
            BOOTSTRAP_REBOOT=true ;;
        s) 
            echo "Skipping hosts configuration"
            BOOTSTRAP_SKIP_HOSTS=true ;;
        *) 
            print_usage
            exit 1 ;;
    esac
done

if [[ ! -z "${BOOTSTRAP_HOSTNAME}" ]]; then
    echo "Setting hostname to ${BOOTSTRAP_HOSTNAME}"
    sudo hostnamectl set-hostname ${BOOTSTRAP_HOSTNAME}
fi

# Adding entries to the host file
if [ ! "${BOOTSTRAP_SKIP_HOSTS}" ]; then
    sudo $HELPERS_PATH/hostsHelper.sh
fi

# Set up SSH server with auth keys from github
echo "Configuring ssh"
if [[ ! -z "${BOOTSTRAP_GH_USER}" ]]; then
    echo "Pulling auth keys from github user ${BOOTSTRAP_GH_USER}"
    ssh-import-id-gh $BOOTSTRAP_GH_USER
fi
sudo cp $SSH_CONFIG_PATH/sshd_config /etc/ssh/sshd_config
sudo systemctl enable sshd && sudo systemctl restart sshd

# Install some packages
sudo apt-get install -y ca-certificates curl apt-transport-https ca-certificates curl gpg nfs-common

# Setup repository for docker
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Setup repository for kube
echo "Setting up kube repository"
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Install and configure zsh and plugins
echo "Installing and configuring zsh..." 
sudo apt-get install zsh -y
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone --depth 1 -- https://github.com/marlonrichert/zsh-autocomplete.git  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autocomplete
cp $ZSH_CONFIG_PATH/zshrc ~/.zshrc
cp $ZSH_CONFIG_PATH/themes/* $ZSH/themes

# Install docker
echo "Installing docker..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Necessary configuration for containerd to work
echo "Configuring containerd for kubernetes"
sudo mkdir -p /etc/containerd/
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

# Install kubernetes  
if [ "$BOOTSTRAP_KUBE_NODE" ]; then
    echo "Installing kubernetes"  
    sudo apt-get install -y kubelet kubeadm kubectl kubectx
    sudo apt-mark hold kubelet kubeadm kubectl
    sudo systemctl enable --now kubelet
fi

sudo apt-get update && sudo apt-get upgrade -y

# Set the default shell to zsh
sudo chsh -s "$(which zsh)" $USER
source ~/.zshrc

echo "Finished installing"
if [ "${BOOTSTRAP_REBOOT}" ]; then
    echo "Rebooting in 5 seconds..."
    sleep 5
    reboot
fi
