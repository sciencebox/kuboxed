## System Architecture
The system consists of three service bubbles matching the provided services: EOS (orange), CERNBOX (blue), and SWAN (green).


        Picture


Each of the three bubbles contains multiple Docker containers that are required to run in order to have the service up and available.
In what follows, a short description of the containers required for each service is provided.

#### EOS
  1. EOS Management Server (MGM): The management node playing the role of the EOS cluster head and storing the namespace (file metadata) information.
  2. EOS File Storage Server (FST): The file server where actual file payload is stored. Multiple instances of the file server container can be executed concurrently so to scale out the storage requirements.


#### CERNBox
  1. CERNBox: The CERNBox Web interface providing sharing capabilities and integration with other applications.
  2. CERNBox Gateway: The proxy redirecting Web traffic to CERNBox backend and file transfers to EOS.
  3. CERNBox MySQL: The MySQL (MariaDB) server providing database backend to CERNBox.


#### SWAN
  1. JupyterHub: The server providing capabilities to spawn, manage, and proxy multiple Jupyter sessions for single users.
  2. EOS Fuse Client: The EOS Fuse client to access EOS as a mounted file system
  3. CVMFS Client: The CVMFS client to access scientific software libraries and packages from the WLCG grid.


-----

## Deployment Guidelines and Requirements
Boxed in Kubernetes meets the requirement of high availability and scalability for production deployments.
Containers are continuously monitored by the Kubernetes master, which restarts the failed ones, while processes inside each container are monitored by a supervisor daemon.
In addition, Boxed in Kubernetes enables the system administrator to scale out storage (by deploying additional EOS File Storage Servers) and computing power (by deploying additional worker nodes for SWAN). Additional information is provided ahead when describing the deployment steps of each service.

The minimal requirements for deploying Boxed in a Kubernetes cluster are as follows.

#### 1. Number of cluster nodes
The minimum amount of nodes is 2, but it is strongly recommended to run the services on 7 or more nodes to isolate system components and avoid single points of failure. The Kubernetes master node is not part of the count.

The provided yaml files for deployment make use of:

  * 1 + N nodes for EOS -- 1 for the Management Server (MGM) and N for N independent File Storage Servers (FST);
  * 2 nodes for CERNBox -- 1 for the CERNBox Backend (Web interface and MySQL database) and 1 for the CERNBox Gateway;
  * 2 nodes for SWAN -- 1 for JupyterHub and 1 playing the role of worker where single-user's sessions are spawned. The worker node executes the containers with the EOS Fuse Client and the CVMFS client.


#### 2. Memory
There is no minimum memory requirement as it mostly relates to the foreseen pool of users and system load.
It is however recommended to:

  * Grant as much memory as possible to the node running the EOS Management Server. The current implementation of EOS loads the entire namespace in memory. While for small deployments 8GB of memory can be sufficient, for bigger deployment it is recommended to monitor the memory consumption and possibly relocate the EOS Management Server on a bigger machine.

  * SWAN worker nodes require an amount of memory proportional to the load they have to sustain and the requirements of jobs executed by users. Adding more worker nodes can alleviate the problem to share the load on a larger pool of machines.


#### 3. Storage
Persistent storage is key for many components of Boxed. While Kubernetes easily relocates containers to other nodes, this does not hold true for storage.

Persistent storage is provided by mounting a *hostPath* volume into the container. This implies that some containers of Boxed are bound to specific nodes of the cluster.
To make the container decoupled from the node, it is highly recommended to use external volumes (e.g., Cinder Volumes in OpenStack clusters), which can be detached and reattached to different nodes if required. More details are provided in Preparation section.

Why not using *PersistentVolumeClaims*?
Please, read the additional Notes on External Capabilities for Network and Persistent Storage.


#### 4. Network
The CERNBox and the SWAN service require to be reachable on usual HTTP and HTTPS ports. 
While it would be possible to use the Kubernetes master as a gateway (leveraging on *NodePort* service type), Kubernetes does not allow to expose ports outside the [30000-32767] range.

Reachability on HTTP and HTTPS ports is achieved by using the *hostNetwork* on the cluster nodes hosting the CERNBox Gateway containers and the JupyterHub container.

No special requirements exist as far as the network speed is concerned. Just remind all the traffic from/to synchronization clients to the CERNBox service is handled by the CERNBox Gateway container.

Why not using external aliases or cloud load balancers? Please, read the additional Notes on External Capabilities for Network and Persistent Storage.


#### *Notes on External Capabilities for Network and Persistent Storage*

To maximize the compatibility of Boxed with diverse public and private clouds, the provided yaml files for deployment do not take advantage of any externally-provided capability such as ingress controllers, external load balancers, persistent volumes, etc.
Such capabilities are typically available on some IaaS clouds only (e.g., Google Compute Engine, Amazon Web Services) and relying on them could constitute a serious obstacle for the deployment of Boxed.


-----

## Preparation for Deployment

### 1. Create the Kubernetes cluster
*You can ignore this step if you have a Kuberenetes cluster already configured. Please, double-check the software versions reported below.*

In order to have single nodes being part of a Kubernetes cluster, specific software must be installed. 

#### Automatic node configuration
Please, consider running the provided script `InitNode.sh` for CentOS 7 based systems to install all the required packages and configure the node as Master or Worker in the scope of the Kubernetes cluster. 
Other Operating Systems will be supported in future. For the time being, please refer to the following "Manual installation" instructions.

#### Manual Installation
Required software:

| Software | Min. Version   |
| -------- | -------------- |
| sudo     | *not-relevant* |
| wget     | *not-relevant* |
| git      | *not-relevant* |
| Docker   | 17.03.2.ce     |
| kubelet  | 1.8.0          |
| kubeadm  | 1.8.0          |
| kubectl  | 1.8.0          |

To install Docker Community Edition (CE), you can refer to the official documentation: https://docs.docker.com/engine/installation/

To initialize a Kubernetes cluster via kubeadm, you can refer to the official guide: https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/ 


#### Kubernetes Network Plugin
Kubernetes requires a third-party network plugin to communicate within the cluster. The deployment of Boxed has been tested with the *Flannel Overlay Network*.
More information available here: https://kubernetes.io/docs/concepts/cluster-administration/networking/#flannel


### 2. Assign containers to cluster nodes
To comply with the persistent storage and network configuration requirements, a univocal assignment between some cluster nodes and the containers they run must be put in place.

Kubernetes provides the ability assign containers to nodes via `kubectl` (https://kubernetes.io/docs/concepts/configuration/assign-pod-node/). To label one node, it is sufficient to issue the command:
```kubectl label nodes <node-name> <label-key>=<label-value>```.


#### Example for assigning a container to a node

The yaml file describing our test application must include the specification:
```
spec:
  nodeSelector:
    nodeApp: TESTAPP
```

To assign the test application container to the node `testcluster.cern.ch`, it is required to label the node consistently:
```
kubectl label node testcluster.cern.ch nodeApp=TESTAPP

kubectl get nodes --show-labels
NAME                          STATUS    ROLES     AGE       VERSION   LABELS
testcluster.cern.ch            Ready     <none>    1d       v1.8.0    beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,kubernetes.io/hostname=testcluster.cern.ch,nodeApp=TESTAPP
```


#### Container assignments required for the deployment of Boxed
The provided yaml files for deployment require several container assignments to cluster nodes.
Even though this can be modified, we recommend following the suggested configuration. Other deployment scenarios have not been tested and might lead to an inconsistent state of services. In case the predefined assignment of containers to nodes cannot be put in place, it is mandatory to satisfy the provisioning of Persistent Volumes and access to Host Network.

Required assignments of containers to nodes:

| Container Name | Label Key | Label Value    | Special Requirements       | Notes |
| --------       | --------- | -------------- | -------------------------- | ----- |
| ldap           | nodeApp   | ldap           | Persistent Storage         |
| eos-mgm        | nodeApp   | eos-mgm        | Memory, Persistent Storage | 1
| eos-fst*N*     | nodeApp   | eos-fst*N*     | Persistent Storage         | 1, 2
| cernbox        | nodeApp   | cernbox        | Persistent Storage         | 3
| cernboxmysql   | nodeApp   | cernbox        | Persistent Storage         | 3
| cernboxgateway | nodeApp   | cernboxgateway | Host Network               |
| swan           | nodeApp   | swan           | Host Network, Persistent Storage |
| swan-daemons   | nodeApp   | swan-users     | Memory | Swan worker nodes for single-user's sessions |

*Note 1*: Persistent Storage is used by EOS to store users' data (by default, two replicas of files are stored on different FSTs) and metadata (namespace stored on the MGM). The loss of either part causes the loss of user files!

*Note 2*: It is recommended to run ONLY one FST on a cluster node to avoid the risk of losing or being unable to access users' data due to node failures. FST containers are "cheap" and can run on small-sized Virtual Machines.

*Note 3*: CERNBox and CERNBox MySQL require Persistent Storage to store sharing information and CERNBox Applications configuration.


### 3. Prepare Persistent Storage
The provisioning of persistent storage is a required step for several containers deployed with Boxed. 
To avoid relying on externally-provided storage (e.g., Google Compute Engine PersistentDisk, Amazon Web Services ElasticBlockStore, Network File System, etc.) that might reduce the deployment scope of Boxed, we limit ourselves to mount a *hostPath* in the running containers. Via *hostPath* it is possible to mount any folder or partition available on the node in the container. Remind that *hostPath* is local storage and cannot be automatically relocated together with the container by Kubernetes.

When deploying Boxed on Virtual Machines (e.g., in a private OpenStack Cloud) it is strongly recommended to attach storage volumes (e.g., a Cinder Volume in OpenStack) to the node and use such volumes in the container. This would allow relocating the storage together with the container in case of node failure. This operation is expected to be performed manually by the system administrator as Kubernetes has no knowledge of attached volumes per se.
Please, read more in the section "How to Fail Over a Node with Persistent Storage Attached".

As a rule of thumb, critical storage (e.g., user account information, user data, sharing database, etc.) should be delivered to attached storage volumes (e.g., Cinder Volumes in OpenStack) and is below identified by a host path in `/mnt/<name-of-the-volume>/<subfolders>`. Less critical persistent storage is instead required for systems logs, which are typically stored on the cluster node itself in the host path `/var/kubeVolumes/<subfolders>`.


#### Required Persistent Storage - **CRITICAL** :

| Container Name | Usage                         | Host Path*                       | Container Path*                 | Cinder Volume Mount Point* | FS   | Size** | Notes |
| --------       | ----------------------------- | -------------------------------- | ------------------------------- | -------------------------- | ---- | ------ | ----- | 
| ldap           | user database                 | /mnt/ldap/userdb                 | /var/lib/ldap                   | /mnt/ldap/                 | ext4 | ~MB    |
| ldap           | ldap configuration            | /mnt/ldap/config                 | /etc/ldap/slapd.d               | /mnt/ldap/                 | ext4 | ~MB    |
| eos-mgm        | namespace                     | /mnt/eos\_namespace              | /var/eos                        | /mnt/mgm\_namepsace        | ext4 | ~GB    |
| eos-fst*N*     | user data                     | /mnt/fst\_userdata               | /mnt/fst\_userdata              | /mnt/fst\_userdata         | xfs  | ~TB/PB | Scalable
| cernbox        | config + user shares (SQLite) | /mnt/cbox\_shares\_db/cbox\_data | /var/www/html/cernbox/data      | /mnt/cbox\_shares\_db      | ext4 | ~MB    |
| cernboxmysql   | config + user shares (MySQL)  | /mnt/cbox_shares_db/cbox_MySQL   | /var/lib/mysql                  | /mnt/cbox\_shares\_db      | ext4 | ~MB    |
| swan           | user status database          | /mnt/jupyterhub\_data            | /srv/jupyterhub/jupyterhub_data | /mnt/jupyterhub\_data      | ext4 | ~MB    |

*Note \**: Whlie host paths and mount points can be modified according to site-specific requirements, never modify the container path.

*Note \*\**: The size reported is the order of magnitude. Actual size depends on system usage, storage requirements, and user pool size.


#### Required Persistent Storage - System Logs :

| Container Name | Usage                         | Host Path*                       | Container Path*                 | Cinder Volume Mount Point* | FS   | Size** | Notes |
| --------       | ----------------------------- | -------------------------------- | ------------------------------- | -------------------------- | ---- | ------ | ----- | 
| eos-mgm        | MGM logs                      | /var/kubeVolumes/mgm_logs        | /var/log/eos                    | --                         | --   | ~GB    |
| eos-mgm        | MQ logs (if colocated w/ MGM) | /var/kubeVolumes/mgm_logs        | /var/log/eos                    | --                         | --   | ~GB    |
| eos-mq         | MQ logs                       | /var/kubeVolumes/mq_logs         | /var/log/eos                    | --                         | --   | ~GB    |
| eos-fst*N*     | FST logs                      | /var/kubeVolumes/fst_logs        | /var/log/eos                    | --                         | --   | ~GB    |
| cernbox        | cernbox logs                  | /mnt/cbox\_shares\_db/cbox\_data | /var/www/html/cernbox/data      | /mnt/cbox\_shares\_db      | ext4 | ~MB    | Colocated with shares db
| cernbox        | httpd logs                    | /var/kubeVolumes/httpd_logs      | /var/log/httpd                  | --                         | --   | ~GB    |
| cernbox        | shibboleth logs               | /var/kubeVolumes/shibboleth_logs | /var/log/shibboleth             | --                         | --   | ~GB    |
| cernboxgateway | nginx logs                    | /var/kubeVolumes/cboxgateway_logs| /var/log/nginx                  | --                         | --   | ~GB    |
| swan           | JupyterHub logs               | /var/kubeVolumes/jupyterhub_logs | /var/log/jupyterhub             | --                         | --   | ~GB    |
| swan           | httpd logs                    | /var/kubeVolumes/httpd_logs      | /var/log/httpd                  | --                         | --   | ~GB    |
| swan           | shibboleth logs               | /var/kubeVolumes/shibboleth_logs | /var/log/shibboleth             | --                         | --   | ~GB    |
| swan-daemons   | eos-fuse logs                 | /var/kubeVolumes/eosfuse_logs    | /var/log/eos/fuse               | --                         | --   | ~GB    |



-----

## Deployment of Services

    WIP



-----

## The Network Perspective

    WIP


-----

## The Storage Perspective

    WIP


### How to Fail Over a Node with Persistent Storage Attached

    WIP

