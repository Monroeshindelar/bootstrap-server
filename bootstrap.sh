#!/bin/bash

BOOTSTRAP_GH_USER=""
BOOTSTRAP_KUBE_NODE=false
BOOTSTRAP_REBOOT=false
BOOTSTRAP_SKIP_HOSTS=false
BOOTSTRAP_SKIP_ZSH=false

IFS=" "
KEEP_ZSHRC="yes"
HOSTS_CONFIG_PATH="hosts"
SSH_CONFIG_PATH="ssh"
ZSH_CONFIG_PATH="zsh"


print_usage() {
    printf "Usage: $(basename) [options...]"
    printf "    -g, --github-user <username>    Github user to use for ssh configuration"
    printf "    -h, --help                      Display this dialogue"
    printf "    -k, --kubernetes                Install and configure for use as as kubernetes node"
    printf "    -n, --name name                 Configure hostname"
    printf "    -r, --reboot                    Reboot when finished"
    printf "    --skip-hosts-configuration      Dont configure hosts file with custom hosts"
    exit 1  
}

print_header() {
    printf "==================================================="    
    printf "==================================================="
    printf "== ____==============_====== _====================="
    printf "==| __ )==___===___=| |_=___| |_=_=__=__=_=_=__===="
    printf "==|  _ \ / _ \ / _ \| __/ __| __| '__/ _\` | '_\ =="
    printf "==| |_) | (_) | (_) | |_\__ \ |_| | | (_| | |_) |=="
    printf "==|____/ \___/ \___/ \__|___/\__|_|  \__,_| .__/ =="
    printf "==========================================|_|======"
    printf "==================================================="    
    printf "==================================================="
}

sudo apt-get update
sudo systemctl daemon-reload

chmod +x $HOSTS_CONFIG_PATH/configureHosts.sh

while test $# -gt 0; do
    case "$1" in
        -h|--help)
            print_usage
            ;;
        -g|--github-user)
            shift
            if test $# -gt 0; then
                BOOTSTRAP_GH_USER=${1}
                echo "Using github user ${BOOTSTRAP_GH_USER} to configure ssh"
            fi
            shift
            ;;
        -k|--kubernetes)
            echo "Is kube node. Will install kubernetes packages"
            BOOTSTRAP_KUBE_NODE=true
            ;;
        -n|--name)
            shift
            if test $# -gt 0; then
                BOOTSTRAP_HOSTNAME=${1}
            fi
            shift
            ;;
        r|--reboot)
            echo "Rebooting when complete"
            BOOTSTRAP_REBOOT=true 
            ;;
        --skip-hosts-configuration)
            echo "Skipping hosts configuration"
            BOOTSTRAP_SKIP_HOSTS=true
            ;;
        --skip-zsh)
            echo "Skipping ZSH installation"
            BOOTSTRAP_SKIP_ZSH=true
            ;;
        *)
            print_usage
            ;;
    esac
done

if [[ ! -z "${BOOTSTRAP_HOSTNAME}" ]]; then
    echo "Setting hostname to ${BOOTSTRAP_HOSTNAME}"
    sudo hostnamectl set-hostname ${BOOTSTRAP_HOSTNAME}
fi

# Adding entries to the host file
if ! ${BOOTSTRAP_SKIP_HOSTS} ; then
    sudo $HOSTS_CONFIG_PATH/configureHosts.sh
fi

# Set up SSH server with auth keys from github
echo "Configuring ssh"
if [[ ! -z "${BOOTSTRAP_GH_USER}" ]]; then
    echo "Pulling auth keys from github user ${BOOTSTRAP_GH_USER}"
    ssh-import-id-gh $BOOTSTRAP_GH_USER
fi
sudo cp $SSH_CONFIG_PATH/sshd_config /etc/ssh/sshd_config
sudo systemctl daemon-reload && sudo systemctl enable sshd && sudo systemctl restart sshd

# Install some packages
sudo apt-get install -y ca-certificates curl apt-transport-https ca-certificates curl gpg nfs-common

# Setup repository for docker
sudo apt-get install ca-certificates curl
sudo install -c -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Setup repository for kube
if [ ${BOOTSTRAP_KUBE_NODE} ]; then
    echo "Setting up kube repository"
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
fi

# Install docker
echo "Installing docker..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Install kubernetes  
if [ ${BOOTSTRAP_KUBE_NODE} ]; then
    # Necessary configuration for containerd to work
    echo "Configuring containerd for kubernetes"
    sudo mkdir -p /etc/containerd/
    containerd config default | sudo tee /etc/containerd/config.toml
    sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

    echo "Installing kubernetes"  
    sudo apt-get install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
    sudo systemctl enable --now kubelet
fi

if [ ! ${BOOTSTRAP_SKIP_ZSH} ]; then
    # Install and configure zsh and plugins
    echo "Installing and configuring zsh..." 
    sudo apt-get install zsh -y
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
    git clone --depth 1 -- https://github.com/marlonrichert/zsh-autocomplete.git  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autocomplete
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
    cp $ZSH_CONFIG_PATH/zshrc ~/.zshrc
    cp $ZSH_CONFIG_PATH/themes/* ~/.oh-my-zsh/themes


    # Set the default shell to zsh
    sudo chsh -s "$(which zsh)" $USER
fi

sudo apt-get update && sudo apt-get upgrade -y

echo "Finished installing"
if  ${BOOTSTRAP_REBOOT} ; then
    echo "Rebooting in 5 seconds..."
    sleep 5
    sudo reboot
fi
