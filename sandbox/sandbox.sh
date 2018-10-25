#!/bin/bash

if [ -f /etc/selinux/config ]; then
  selinuxchk=`sudo cat /etc/selinux/config | grep enforcing`
  selinux_chk=`echo -e $?`
  if [ $selinux_chk = "0" ]; then
    sudo sed -i.bak 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    sudo setenforce 0
  fi
fi

cd /home/opc/
setenforce 0

## Install Java
yum -y install java-1.8.0-openjdk.x86_64

## Disable Transparent Huge Pages
echo never | tee -a /sys/kernel/mm/transparent_hugepage/enabled
echo "echo never | tee -a /sys/kernel/mm/transparent_hugepage/enabled" | tee -a /etc/rc.local

## Set vm.swappiness to 1
echo vm.swappiness=1 | tee -a /etc/sysctl.conf
echo 1 | tee /proc/sys/vm/swappiness

## Tune system network performance
echo net.ipv4.tcp_timestamps=0 >> /etc/sysctl.conf
echo net.ipv4.tcp_sack=1 >> /etc/sysctl.conf
echo net.core.rmem_max=4194304 >> /etc/sysctl.conf
echo net.core.wmem_max=4194304 >> /etc/sysctl.conf
echo net.core.rmem_default=4194304 >> /etc/sysctl.conf
echo net.core.wmem_default=4194304 >> /etc/sysctl.conf
echo net.core.optmem_max=4194304 >> /etc/sysctl.conf
echo net.ipv4.tcp_rmem="4096 87380 4194304" >> /etc/sysctl.conf
echo net.ipv4.tcp_wmem="4096 65536 4194304" >> /etc/sysctl.conf
echo net.ipv4.tcp_low_latency=1 >> /etc/sysctl.conf

## Tune File System options
sed -i "s/defaults        1 1/defaults,noatime        0 0/" /etc/fstab

## Firewall Setup
firewall_on="1"
if [ $firewall_on = "1" ]; then
  echo -e "\tSetting up Firewall Ports"
  echo -e "Port 7180"
  firewall-cmd --zone=public --add-port=7180/tcp
  echo -e "Port 8888"
  firewall-cmd --zone=public --add-port=8888/tcp
  echo -e "Port 80"
  firewall-cmd --zone=public --add-port=80/tcp
  firewall-cmd --runtime-to-permanent
  echo -e "DONE"
else
  systemctl stop firewalld
  systemctl disable firewalld
fi

echo -e "Installing Docker..."
yum -y install docker.x86_64
systemctl start docker

echo "In check logic..."
statuschk=`echo -e $?`
if [ $statuschk = "0" ]; then
  continue
else
  while [ $statuschk != "0" ]; do
    systemctl restart docker
    statuschk=`echo -e $?`
    sleep 1
  done;
fi

echo -e "Downloading CDH5 Docker Container..."
wget https://downloads.cloudera.com/demo_vm/docker/cloudera-quickstart-vm-5.13.0-0-beta-docker.tar.gz
tar -zxvf cloudera-quickstart-vm-5.13.0-0-beta-docker.tar.gz
docker import - cloudera/quickstart:latest < cloudera-quickstart-vm-*-docker/*.tar

echo -e "Starting CDH5 Docker Container..."
quickstart_id=`docker images | sed 1d | gawk '{print $3}'`
docker run -d --hostname=quickstart.cloudera --privileged=true -it -p 7180:7180 -p 80:80 -p 8888:8888 ${quickstart_id} /usr/bin/docker-quickstart

echo -e "Waiting 120 seconds on startup..."
t=0
while [ $t -le 120 ]; do
  echo -e "$t"
  sleep 5
  t=$((t+5))
done;

echo -e "Starting CDH Manager..."
quickstart_ps=`docker ps | sed 1d | gawk '{print $1}'`
docker exec -it ${quickstart_ps} /home/cloudera/cloudera-manager --express

## Add Cloudera user and sudo privileges
useradd -s /bin/bash cloudera
mkdir -p /home/cloudera/.ssh
cp /home/opc/.ssh/authorized_keys /home/cloudera/.ssh/
chown cloudera:cloudera -R /home/cloudera
echo "cloudera    ALL=(ALL)       ALL" >> /etc/sudoers
