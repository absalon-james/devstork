#!/bin/bash

status_file=/tmp/userdata_status
echo "RUNNING" > ${status_file}

HAYSTACK=/var/log/cloud-init.log
NEEDLE="backgrounded Resizing took"

echo "Waiting for background resizing to finish" > ${status_file}
while [ $(grep "$NEEDLE" $HAYSTACK -i --count) -eq "0" ]; do
    echo "Waiting for backgrouded Resizing to finish"
    sleep 5
done

# Make the stack user
useradd stack -d /home/stack -s /bin/bash -g sudo
mkdir -p /home/stack
chown -R stack /home/stack
chown stack /tmp/userdata_status
echo "# User rules for root" >> /etc/sudoers.d/90-stack-user
echo "stack ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/90-stack-user
chmod 440 /etc/sudoers.d/90-stack-user

echo "Installing software before devstack" > ${status_file}
# Required software
apt-get update
apt-get install -y git python-pip lvm2 vim squid3

echo "Creating logical volumes on ssds" > ${status_file}
# Init the ssd space on the baremetal io
pvcreate /dev/sdb
pvcreate /dev/sdc
vgcreate ssdpool /dev/sdb /dev/sdc
lvcreate -L 1024G -n ssd1 ssdpool
mkfs.ext4 /dev/mapper/ssdpool-ssd1
mount -t ext4 /dev/mapper/ssdpool-ssd1 /opt

cat <<'EOF' >> /home/stack/init.sh
#!/bin/bash
{
    set -x
    status_file=/tmp/userdata_status
    # Upgrade setuptools
    sudo pip install --upgrade setuptools
    sudo pip install --upgrade decorator
    sudo pip install --upgrade i18n

    # grant external access to vms
    echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward
    sudo iptables -t nat -A POSTROUTING -o bond0.101 -j MASQUERADE

    cd /home/stack
    ssh-keygen -t rsa -N "" -f /home/stack/.ssh/id_rsa

    # Clone devstack and checkout specific version
    git clone https://github.com/openstack-dev/devstack.git
    cd devstack
    git remote update
    git checkout stable/icehouse

    # Write contents of local.conf file
    echo "[[local|localrc]]" >> local.conf
    echo "ADMIN_PASSWORD=secrete" >> local.conf
    echo "DATABASE_PASSWORD=\$ADMIN_PASSWORD" >> local.conf
    echo "RABBIT_PASSWORD=\$ADMIN_PASSWORD" >> local.conf
    echo "SERVICE_PASSWORD=\$ADMIN_PASSWORD" >> local.conf
    echo "SERVICE_TOKEN=c324b782-43a9-24c1-c2c4-d513c4041b42" >> local.conf
    echo "disable_service n-net" >> local.conf
    echo "enable_service q-svc" >> local.conf
    echo "enable_service q-agt" >> local.conf
    echo "enable_service q-dhcp" >> local.conf
    echo "enable_service q-l3" >> local.conf
    echo "enable_service q-meta" >> local.conf
    echo "enable_service neutron" >> local.conf
    echo "HOST_IP=$(ifconfig bond0.101 | awk '/inet addr/{print substr($2,6)}')" >> local.conf

    # Run devstack's stack.sh script
    echo "Stacking devstack" > ${status_file}
    ./stack.sh

    #source openrc admin admin secrete

    export OS_USERNAME=admin
    export OS_TENANT_NAME=admin
    export OS_PASSWORD=secrete
    export OS_AUTH_URL=http://$(ifconfig bond0.101 | awk '/inet addr/{print substr($2,6)}'):5000/v2.0

    # add keypair
    nova keypair-add heat-key --pub-key /home/stack/.ssh/id_rsa.pub

    # add ssh and ping to default security rules
    nova secgroup-add-rule default tcp 22 22 0.0.0.0/0
    nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0
    glance image-create --name "Ubuntu 12.04 software config" --disk-format qcow2 --location http://ab031d5abac8641e820c-98e3b8a8801f7f6b990cf4f6480303c9.r33.cf1.rackcdn.com/ubuntu-softwate-config.qcow2 --is-public True --container-format bare
} 2>&1 >> /home/stack/init-log
    echo "FINISHED" > ${status_file}
EOF

chmod o+x /home/stack/init.sh
chown stack /home/stack/init.sh

su stack -c "at -f /home/stack/init.sh now + 1 minute"
echo "Scheduled devstack" > ${status_file}
