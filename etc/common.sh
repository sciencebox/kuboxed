#!/bin/bash
# Shared variables and functions


# ----- Variables ----- #
SUPPORTED_HOST_OS=(centos7)
SUPPORTED_NODE_TYPES=(master worker)

BASIC_SOFTWARE="wget git sudo "

DOCKER_VERSION="-17.03.2.ce"
KUBE_VERSION="-1.9.5-0"

OS_RELEASE="/etc/os-release"

# Versions







# ----- Functions ----- #

# Check to be root
need_root ()
{
  if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
  fi
}



# Disable SELinux if needed
disable_selinux ()
{
  test $(getenforce) == "Disabled" || setenforce 0
}



# (try to) Detect the OS
detect_os ()
{
  # TODO: not used
  source $OS_RELEASE
  echo $ID$VERSION_ID
}



# Check if the node type was properly set
check_kube_node_type () 
{
  if [[ -z $KUBE_NODE_TYPE ]]; then
    echo "ERROR: KUBE_NOTE_TYPE not set."
    echo "Please set the node type with 'export KUBE_NODE_TYPE=<master||worker>'"
    echo "Cannot continue."
    exit -1
  fi

  # If the env var is set, check to have a valid name
  for ntype in ${SUPPORTED_NODE_TYPES[*]};
  do
    if [[ "$ntype" == "$KUBE_NODE_TYPE" ]]; then
      echo "Configuring this machine as ${ntype}."
      return
    fi
  done

  echo "ERROR: Invalid node type set."
  echo "Please set the node type with 'export KUBE_NODE_TYPE=<master||worker>'"
  echo "Cannot continue."
  exit -1
}



# Check if the host OS is supported
check_host_os_type ()
{
  if [[ -z $HOST_OS ]]; then
    echo "ERROR: HOST_OS not set."
    echo "Cannot continue."
    exit -1
  fi

  # If the env var is set, check to have a supported OS
  for ostype in ${SUPPORTED_HOST_OS[*]};
  do
    if [[ "$ostype" == "$HOST_OS" ]]; then
      return
    fi
  done

  echo "ERROR: Unsupported host os."
  echo "Supported OS: ${SUPPORTED_HOST_OS[*]}"
  echo "Cannot continue."
  exit -1
}



# Configure iptables to make the master reachable on TCP 6443 and TCP 10250
configure_iptables ()
{
# Completely disable iptables and firewalld
# There are issues with the DNS container and flannel
# k8s.io/dns/vendor/k8s.io/client-go/tools/cache/reflector.go:94: Failed to list *v1.Endpoints: Get https://10.96.0.1:443/api/v1/endpoints?resourceVersion=0: dial tcp 10.96.0.1:443: getsockopt: no route to host

  #TODO: Implement for Ubuntu
  systemctl stop iptables && systemctl disable iptables
  systemctl stop firewalld && systemctl disable firewalld

  # Properly set bridge-nf-call when SELinux is enforcing and firewalld is running
  sysctl net.bridge.bridge-nf-call-iptables=1
  sysctl net.bridge.bridge-nf-call-ip6tables=1

  # Set policy on FORWARD chain
  iptables --policy FORWARD ACCEPT      # See issue: https://github.com/kubernetes/kubernetes/issues/40182

: '''
# Could be of inspiration to configure at a finer grain, instead of disabling entire services
        TCP_PORTS_MASTER="2379 2380 6443 10250 10251 10252 10255 "
        TCP_PORTS_WORKER=" 10250 10255 "
        IFACE="eth0"

        echo ""
        echo "Configuring iptables..."

        # Different ports to be opened according to the node type
        if [[ "$1" == "master" ]]; then
                TCP_PORTS=$TCP_PORTS_MASTER
        elif [[ "$1" == "worker" ]]; then
                TCP_PORTS=$TCP_PORTS_WORKER
        else
                echo "WARNING: unknown node type. iptables left unchanged."
                TCP_PORTS=""
        fi

        # Add rules to iptables
        for port in $TCP_PORTS
        do
                iptables -I INPUT -i $IFACE -p tcp --dport $port -j ACCEPT
        done

        # Properly set bridge-nf-call when SELinux is enforcing and firewalld is running
        sysctl net.bridge.bridge-nf-call-iptables=1
        sysctl net.bridge.bridge-nf-call-ip6tables=1
'''
}




# Install the basic software
install_basics()
{
  echo ""
  echo "Installing the basics..."

  if [[ "$HOST_OS" == "centos7" ]]; then
    yum install -y $BASIC_SOFTWARE
  elif [[ "$HOST_OS" == "ubuntu" ]]; then
    apt-get install -y $BASIC_SOFTWARE
  else
    echo "Unknown OS. Cannot continue."
    exit 1
  fi
}



# Install Docker
install_docker()
{
  echo ""
  echo "Installing Docker..." 

  if [[ "$HOST_OS" == "centos7" ]]; then
    mkdir -p /var/lib/docker
    yum install -y yum-utils \
      device-mapper-persistent-data \
      lvm2
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    disable_selinux
    # See dependency issue: https://github.com/moby/moby/issues/33930
    yum install -y --setopt=obsoletes=0 \
      docker-ce${DOCKER_VERSION} \
      docker-ce-selinux${DOCKER_VERSION}
    systemctl enable docker && systemctl start docker
    systemctl status docker

  elif [[ "$HOST_OS" == "ubuntu" ]]; then
    echo ""
    # TODO: To be implemented

  else
    echo "Unknown OS. Cannot continue."
    exit 1
  fi
}



# Install Kubernetes
install_kubernetes ()
{
  echo ""
  echo "Installing kubernetes..."

  if [[ "$HOST_OS" == "centos7" ]]; then
    cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
	https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

    disable_selinux
    yum install -y \
      kubelet${KUBE_VERSION} \
      kubeadm${KUBE_VERSION} \
      kubectl${KUBE_VERSION}
    systemctl enable kubelet && systemctl start kubelet
    systemctl status kubelet

  elif [[ "$HOST_OS" ==  "ubuntu" ]]; then
    apt-get update && apt-get install -y apt-transport-https
    wget -q https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
    cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
    apt-get update
    apt-get install -y kubelet kubeadm

  else
    echo "Unknown OS. Cannot continue."
    exit 1
  fi
}



# Configure kubelet with the cgroup driver used by docker
set_kubelet_cgroup_driver ()
{
  #TODO: Implement for Ubuntu

  echo ""
  echo "Configuring cgroup driver for kubelet service..."

  CGROUP_DRIVER=`docker info | grep -i cgroup | cut -d : -f 2 | tr -d " "`
  if [[ ! -f /etc/systemd/system/kubelet.service.d/10-kubeadm.conf.MASTER ]]; then
    cp /etc/systemd/system/kubelet.service.d/10-kubeadm.conf /etc/systemd/system/kubelet.service.d/10-kubeadm.conf.MASTER
    sed -i "s/Environment=\"KUBELET_CGROUP_ARGS=--cgroup-driver=systemd\"/\n\#Environment=\"KUBELET_CGROUP_ARGS=--cgroup-driver=systemd\"\nEnvironment=\"KUBELET_CGROUP_ARGS=--cgroup-driver=${CGROUP_DRIVER}\"\n/" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
  else
    sed "s/Environment=\"KUBELET_CGROUP_ARGS=--cgroup-driver=systemd\"/\n\#Environment=\"KUBELET_CGROUP_ARGS=--cgroup-driver=systemd\"\nEnvironment=\"KUBELET_CGROUP_ARGS=--cgroup-driver=${CGROUP_DRIVER}\"\n/" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf.MASTER > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
  fi

  systemctl daemon-reload
  service kubelet restart
}



# Start the cluster with Flannel pod network
start_kube_masternode ()
{
  #TODO: Implement for Ubuntu

  if [[ "$KUBE_NODE_TYPE" == "master" ]]; then
    echo ""
    echo "Initializing the cluster..."
    kubeadm init --pod-network-cidr=10.244.0.0/16 --token-ttl 0

    # This can be run as any user (root works as well)
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    # Use the Flannel pod network
    echo ""
    echo "Installing the Flannel pod network..."
    kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.10.0/Documentation/kube-flannel.yml

    # Restart kubelet to mak sure it picks up the extra config files
    # NOTE: This is mission-critical for hostPort and iptables mapping on kubernetes managed containers
    systemctl daemon-reload
    service kubelet restart
  fi
}


