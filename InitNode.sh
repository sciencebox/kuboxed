#!/bin/bash

### Usage ###
#
# Please define an environment variable named KUBE_NODE_TYPE to distinguish between master and worker nodes
#	E.g., export KUBE_NODE_TYPE=worker
# Run ./InitNode.sh to install the required software
#
# The master node will provide further instructions on how to have other nodes joining the cluster
# Please run the required commands on worker nodes and check their status from the master with `kubectl get nodes`
#
###

source etc/common.sh

# TODO: Currently only centos7 is supported 
export HOST_OS="centos7"

need_root
check_kube_node_type
check_host_os_type
install_basics
install_docker
install_kubernetes
configure_iptables
set_kubelet_cgroup_driver
start_kube_masternode	# Depends on KUBE_NODE_TYPE

