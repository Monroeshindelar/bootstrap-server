#!/bin/bash

IFS=" " 
SSH_CONFIG_PATHo="ssh"
ZSH_CONFIG_PATH="zsh"

print_usage() {
    printf "Usage: ..."
}

while getopts 'gh' flag; do
    case "${flag}" in
        g) BOOTSTRAP_GH_USER=${OPTARG} ;;
        h) BOOTSTRAP_HOSTNAME=${OPTARG} ;;
        *) print_usage
           exit 1 ;;
    esac
done

if [ -z "${BOOTSTRAP_HOSTNAME}" ];
    echo "Setting hostname to ${BOOTSTRAP_HOSTNAME}"
    hostnamectl set-hostname ${BOOTSTRAP_HOSTNAME}
fi

# Adding entries to the host file
cat "# Added by bootstrap script" >> /etc/hosts
cat "127.0.1.1  ${hostname}.local   ${hostname}" >> /etc/hosts

while read -ra line; do
    name=${lines[0]}
    ip=${lines[1]}

    if [ "${hostname}" != "$name" ] then;
        cat "${ip}  ${name}.local  ${name}" >> /etc/hosts
    fi
done < hosts/hosts


# Set up SSH server with auth keys from github
echo "Configuring ssh"
if [-z "${BOOTSTRAP_GH_USER}" ];
    echo "Pulling auth keys from github user ${BOOTSTRAP_GH_USER}"
    ssh-import-id-gh $BOOTSTRAP_GH_USER
fi
cp $SSH_CONFIG_PATH/sshd_config /etc/sshd_config
systemctl enable sshd && systemctl restart sshd

# Install some packages
apt-get update
apt-get install -y ca-certificates curl apt-transport-https ca-certificates curl gpg nfs-common

# Setup repository for docker
echo "Setting up docker repository"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# Setup repository for kube
echo "Setting up kube repository"
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update

# Install and configure zsh and plugins
echo "Installing and configuring zsh..."
apt-get install zsh -y
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone --depth 1 -- https://github.com/marlonrichert/zsh-autocomplete.git  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autocomplete
cp $ZSH_CONFIG_PATH/zshrc ~/.zshrc
cp $ZSH_CONFIG_PATH/themes/* $ZSH/themes/

# Install docker
echo "Installing docker..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Necessary configuration for containerd to work
echo "Configuring containerd for kubernetes"
mkdir -p /etc/containerd/
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

# Install kubernetes
echo "Installing kubernetes"
apt-get update
apt-get install -y kubelet kubeadm kubectl kubectx
apt-mark hold kubelet kubeadm kubectl
systemctl enable --now kubelet

apt-get update && apt-get upgrade -y
source ~/.zshrc

reboot