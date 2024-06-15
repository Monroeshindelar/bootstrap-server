#!/bin/bash

echo "Configuring hosts file"
echo "# Added by bootstrap script" >> /etc/hosts
echo "127.0.1.1  $(hostname).local   $(hostname)" >> /etc/hosts

while read -ra line; do
    name=${line[0]}
    ip=${line[1]}

    if [ "$(hostname)" != "$name" ]; then
        echo "Configuring host for ${name}"
        echo "${ip}  ${name}.local  ${name}" >> /etc/hosts
    fi
done < hosts/hosts
