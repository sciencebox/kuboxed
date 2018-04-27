# Welcome to BOXED
### *KuBoxed -- Scalable Deployment with Kubernetes*

-----

https://cernbox.cern.ch/cernbox/doc/boxed

Self-contained, containerized package for next-generation cloud storage and computing services for scientific and general-purpose use:

 - CERNBox: https://cernbox.web.cern.ch
 - EOS: https://eos.web.cern.ch
 - SWAN: https://swan.web.cern.ch
 - CVMFS: https://cvmfs.web.cern.ch


Packaging by: Enrico Bocchi, Hugo Gonzalez Labrador, Jozsef Makai, Jakub T. Moscicki


-----

## System Architecture
The system consists of three service blocks matching the provided services: EOS (red), CERNBOX (green), and SWAN (orange).

![System Architecture](https://raw.githubusercontent.com/cernbox/kuboxed/master/docs/architecture.png)

Each of the three blocks contains multiple Docker containers that are required to run in order to have the services up and available.
In what follows, a short description of the containers required for each service is provided.

#### EOS
  1. EOS Management Server (MGM): The management node playing the role of the EOS cluster head and storing the namespace (file metadata) information.
  2. EOS File Storage Server (FST): The file server where actual file payload is stored. Multiple instances of the file server container can be executed concurrently so to scale out the storage requirements.

*Note*: EOS also requires a messaging queue process (MQ) that is in charge of deliverying the messages among the MGM and all the FSTs. Such process can be executed on a separated container or on the MGM container. The configuration provided below executes the MQ process inside the MGM container.


#### CERNBox
  1. CERNBox: The CERNBox Web interface providing sharing capabilities and integration with other applications.
  2. CERNBox Gateway: The proxy redirecting Web traffic to CERNBox backend and file transfers to EOS.
  3. CERNBox MySQL: The MySQL (MariaDB) server providing database backend to CERNBox.


#### SWAN
  1. JupyterHub: The server providing capabilities to spawn, manage, and proxy multiple Jupyter sessions for single users.
  2. EOS Fuse Client: The EOS Fuse client to access EOS as a mounted file system
  3. CVMFS Client: The CVMFS client to access scientific software libraries and packages from the WLCG grid.


#### LDAP
As satellite service, a local LDAP server is required by EOS, CERNBox, and SWAN to fetch user's information.


-----

## Deployment Guidelines and Requirements
Boxed in Kubernetes meets the requirement of high availability and scalability for production deployments.
Containers are continuously monitored by the Kubernetes master, which restarts the failed ones, while processes inside each container are monitored by a supervisor daemon.
In addition, Boxed in Kubernetes enables the system administrator to scale out storage (by deploying additional EOS File Storage Servers) and computing power (by deploying additional worker nodes for SWAN). Additional information is provided ahead when describing the deployment steps of each service.

The minimal requirements for deploying Boxed in a Kubernetes cluster are as follows.

#### 1. Number of cluster nodes
It is strongly recommended to run the services on 8 (or more) nodes to isolate system components and avoid single points of failure. The Kubernetes master node is not part of the count.

The provided yaml files for deployment make use of:

  * 1 node for LDAP -- 1 for the local LDAP database to store user's information;
  * 1 + N nodes for EOS -- 1 for the Management Server (MGM) and N for N independent File Storage Servers (FST);
  * 2 nodes for CERNBox -- 1 for the CERNBox Backend (core ownCloud, Web interface, and MySQL database) and 1 for the CERNBox Gateway (nginx reverse proxy sorting different traffic types);
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
Please, refer to "Notes on External Capabilities for Network and Persistent Storage" for more information.


#### 4. Network
The CERNBox and the SWAN service require to be reachable on usual HTTP and HTTPS ports. 
While it would be possible to use the Kubernetes master as a gateway (leveraging on *NodePort* service type), Kubernetes does not allow to expose ports outside the [30000-32767] range.

Reachability on HTTP and HTTPS ports is achieved by using the *hostNetwork* on the cluster nodes hosting the CERNBox Gateway containers and the JupyterHub container.

No special requirements exist as far as the network speed is concerned. Just remind all the traffic from/to synchronization clients to the CERNBox service is handled by the CERNBox Gateway container.

Why not using external aliases or cloud load balancers? Please, read "Notes on External Capabilities for Network and Persistent Storage" for more information.


#### *Notes on External Capabilities for Network and Persistent Storage*

To maximize the compatibility of Boxed with diverse public and private clouds, the provided yaml files for deployment do not take advantage of any externally-provided capability such as ingress controllers, external load balancers, persistent volumes, etc.
Such capabilities are typically available on some IaaS clouds only (e.g., Google Compute Engine, Amazon Web Services) and relying on them would constitute an obstacle for the deployment of Boxed on other clouds.



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
To comply with the persistent storage and network configuration requirements, a univocal assignment between cluster nodes and the containers they run must assured.
Kubernetes provides the ability assign containers to nodes via `kubectl` (https://kubernetes.io/docs/concepts/configuration/assign-pod-node/). 

To label one node, it is sufficient to issue the command:
```kubectl label node <node-name> <label-key>=<label-value>```.


#### Example for assigning a container to a node

The yaml file describing our test application must include the specification:
```
spec:
  nodeSelector:
    nodeApp: TESTAPP
```

To assign the test application container to the node `testnode.cern.ch`, it is required to label the node consistently:
```
kubectl label node testnode.cern.ch nodeApp=TESTAPP

kubectl get nodes --show-labels
NAME                        STATUS    ROLES     AGE      VERSION   LABELS
testnode.cern.ch            Ready     <none>    1d       v1.8.0    beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,kubernetes.io/hostname=testnode.cern.ch,nodeApp=TESTAPP
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
To avoid relying on externally-provided storage (e.g., Google Compute Engine PersistentDisk, Amazon Web Services ElasticBlockStore, Network File System, etc.), we limit ourselves to mount a *hostPath* in the running containers (see "Notes on External Capabilities for Network and Persistent Storage"). Via *hostPath* it is possible to mount any folder available on the node in the container. Remind that *hostPath* is local storage and cannot be automatically relocated together with the container by Kubernetes.

When deploying Boxed on Virtual Machines (e.g., in a private OpenStack Cloud) it is strongly recommended to attach storage volumes (e.g., a Cinder Volume in OpenStack) to the node and use such volumes in the container. This would allow relocating the storage volume together with the container in case of node failure. This operation is expected to be performed manually by the system administrator as Kubernetes has no knowledge of attached volumes per se.
Please, read more in the section "How to Fail Over a Node with Persistent Storage Attached".

As a rule of thumb, critical storage (e.g., user account information, user data, sharing database, etc.) should be stored on attached volumes (e.g., Cinder Volumes in OpenStack) and is below identified by a host path in `/mnt/<name-of-the-volume>/<subfolders>`. Less critical persistent storage is instead required for systems logs, which are typically stored on the cluster node itself in the host path `/var/kubeVolumes/<subfolders>`.


#### Required Persistent Storage - **CRITICAL** :

| Container Name | Usage                         | Host Path*                       | Container Path*                 | Cinder Volume Mount Point* | FS   | Size** | Notes |
| --------       | ----------------------------- | -------------------------------- | ------------------------------- | -------------------------- | ---- | ------ | ----- | 
| ldap           | user database                 | /mnt/ldap/userdb                 | /var/lib/ldap                   | /mnt/ldap/                 | ext4 | ~MB    |
| ldap           | ldap configuration            | /mnt/ldap/config                 | /etc/ldap/slapd.d               | /mnt/ldap/                 | ext4 | ~MB    |
| eos-mgm        | namespace                     | /mnt/eos_namespace               | /var/eos                        | /mnt/mgm_namepsace         | ext4 | ~GB    |
| eos-fst*N*     | user data                     | /mnt/fst_userdata                | /mnt/fst_userdata               | /mnt/fst_userdata          | xfs  | ~TB/PB | Scalable
| cernbox        | config + user shares (SQLite) | /mnt/cbox_shares_db/cbox_data    | /var/www/html/cernbox/data      | /mnt/cbox_shares_db        | ext4 | ~MB    |
| cernboxmysql   | config + user shares (MySQL)  | /mnt/cbox_shares_db/cbox_MySQL   | /var/lib/mysql                  | /mnt/cbox_shares_db        | ext4 | ~MB    |
| swan           | user status database          | /mnt/jupyterhub_data             | /srv/jupyterhub/jupyterhub_data | /mnt/jupyterhub_data       | ext4 | ~MB    |

*Note \**: While host paths and mount points can be modified according to site-specific requirements, never modify the container path.

*Note \*\**: The size reported is the order of magnitude. Actual size depends on system usage, storage requirements, and user pool size.

**WARNING**:
Subfolders in `/mnt/<name-of-the-volume>` are NOT automatically created at the time of deployment.
Please, proceed as follows:
1. Attach, mount, and format the external volumes to the nodes where containers requiring critical persistent storage will execute;
2. Create the required subfolders:
  * `/mnt/ldap/userdb` and `/mnt/ldap/config` for LDAP;
  * `/mnt/cbox_shares_db/cbox_data` and `/mnt/cbox_shares_db/cbox_MySQL` for CERNBox;
3. Deploy the service (see below "Deployment of Services").

If the deployment of services fails, please inspect the pod status and look for errors related to mount of volumes.

Below, an example of failed deployment for service LDAP because of subfolders not pre-created.
1. Pod for LDAP hangs in status "ContainerCreating":
```
# kubectl -n boxed get pods -o wide -a
NAME      READY     STATUS              RESTARTS   AGE       IP        NODE
ldap      0/1       ContainerCreating   0          7s        <none>    kubedevel-worker1.cern.ch
```
2. Inspect the Pod status with `# kubectl -n boxed describe pod ldap` and look at the list of events provided at the bottom:
```
Events:
  Type     Reason                 Age              From                                Message
  ----     ------                 ----             ----                                -------
  Normal   Scheduled              3s               default-scheduler                   Successfully assigned ldap to kubedevel-worker1.cern.ch
  Normal   SuccessfulMountVolume  2s               kubelet, kubedevel-worker1.cern.ch  MountVolume.SetUp succeeded for volume "default-token-2vvcr"
  Warning  FailedMount            1s (x3 over 2s)  kubelet, kubedevel-worker1.cern.ch  MountVolume.SetUp failed for volume "ldap-config" : hostPath type check failed: /mnt/ldap/config is not a directory
  Warning  FailedMount            1s (x3 over 2s)  kubelet, kubedevel-worker1.cern.ch  MountVolume.SetUp failed for volume "ldap-userdb" : hostPath type check failed: /mnt/ldap/userdb is not a directory
```


#### Required Persistent Storage - System Logs :

| Container Name | Usage                         | Host Path*                       | Container Path*                 | Cinder Volume Mount Point* | FS   | Size** | Notes |
| --------       | ----------------------------- | -------------------------------- | ------------------------------- | -------------------------- | ---- | ------ | ----- | 
| eos-mgm        | MGM logs                      | /var/kubeVolumes/mgm_logs        | /var/log/eos                    | --                         | --   | ~GB    |
| eos-mgm        | MQ logs (if colocated w/ MGM) | /var/kubeVolumes/mgm_logs        | /var/log/eos                    | --                         | --   | ~GB    |
| eos-mq         | MQ logs                       | /var/kubeVolumes/mq_logs         | /var/log/eos                    | --                         | --   | ~GB    |
| eos-fst*N*     | FST logs                      | /var/kubeVolumes/fst_logs        | /var/log/eos                    | --                         | --   | ~GB    |
| cernbox        | cernbox logs                  | /mnt/cbox_shares_db/cbox_data    | /var/www/html/cernbox/data      | /mnt/cbox_shares_db        | ext4 | ~MB    | Colocated with shares db
| cernbox        | httpd logs                    | /var/kubeVolumes/httpd_logs      | /var/log/httpd                  | --                         | --   | ~GB    |
| cernbox        | shibboleth logs               | /var/kubeVolumes/shibboleth_logs | /var/log/shibboleth             | --                         | --   | ~GB    |
| cernboxgateway | nginx logs                    | /var/kubeVolumes/cboxgateway_logs| /var/log/nginx                  | --                         | --   | ~GB    |
| swan           | JupyterHub logs               | /var/kubeVolumes/jupyterhub_logs | /var/log/jupyterhub             | --                         | --   | ~GB    |
| swan           | httpd logs                    | /var/kubeVolumes/httpd_logs      | /var/log/httpd                  | --                         | --   | ~GB    |
| swan           | shibboleth logs               | /var/kubeVolumes/shibboleth_logs | /var/log/shibboleth             | --                         | --   | ~GB    |
| swan-daemons   | eos-fuse logs                 | /var/kubeVolumes/eosfuse_logs    | /var/log/eos/fuse               | --                         | --   | ~GB    |



-----

## Deployment of Services

In what follows, it is assumed that the Kubernetes cluster is already up and running, that a sufficient number of nodes are provided for the deployment of Boxed, and that the persistent volumes are already attached and formatted accordingly to the tables above.

The three services (and single containers for each service) should be deployed in a specific order to satisfy the dependencies among them. Specifically:
  1. All the services (EOS, CERNBox, and SWAN) refer to a common LDAP server to get user information. The LDAP server must, therefore, be the first component deployed in your cluster;
  2. EOS should be the first service being deployed as it constitutes the common backend storage for both CERNBox and SWAN;
  3. CERNBox and SWAN can be deployed independently one of the other.

In addition, all the services operate in the namespace called `boxed`, which is created on purpose to easily account for the resources consumed by EOS, CERNBox, and SWAN in clusters shared by multiple deployments.

To deploy the service, from a high-level perspective, it is sufficient to create the resources described in the provided yaml files. Overall, six steps are required:
  1. `BOXED.yaml`
  2. `LDAP.yaml`
  3. `eos-storage-mgm.yaml`
  4. `eos-storage-fstN.yaml` (to be created with the provided script eos-storage-fst.sh)
  5. `CERNBOX.yaml`
  6. `SWAN.yaml`

It is recommended to follow the detailed instructions below, which contain also results of commands from a working deployment useful for sanity check.



### 1. Initialization of the namespace and deployment of LDAP server
Create the resources described in `BOXED.yaml`:
```
kubectl create -f BOXED.yaml
```
This creates the `boxed` namespace and creates secrets for web servers (CERNBox, CERNBox Gateway, JupyterHub). Remind that the provided certificates are self-signed, do not match the hostname of the machine where Boxed is being deployed, and are not trusted. Therefore, web browsers will complain when accessing Boxed webpages. Please, consider replacing them with proper certificates.

To deploy the LDAP server, create the resources described in `LDAP.yaml` to start the LDAP server.
```
kubectl create -f LDAP.yaml
```
The LDAP container will be downloaded and run on a node labeled with `nodeApp=ldap`. The container folders `/var/lib/ldap` and `/etc/ldap/slapd.d` must be stored on persistent media.
Also, a Kubernetes service named `ldap` will be created to access the server from other containers of the cluster at `ldap.boxed.svc.cluster.local`.

Consider adding some demo users to the LDAP server when deploying Boxed for the first time.
The script at `/root/addusers.sh` on the LDAP container will automatically create 10 users accounts and a special user account with administrator privileges.

To access CERNBox and SWAN services, please use the following user information **(username:password)**:
  * user0:test0
  * user1:test1
  * ...
  * user9:test9



### 2. Deployment of EOS
EOS is deployed using Pods and requires several manual steps to be performed by the system administrator to make the network configuration and the storage persistent.


#### a. EOS Management Server (MGM)
Create the EOS Management Server (MGM) via the file `eos-storage-mgm.yaml`. 
The EOS-MGM container will be downloaded and run on a node labeled with `nodeApp=eos-mgm`.
Also, a heaedless Kubernetes service will grant access to it at `eos-mgm.boxed.svc.cluster.local`. 
Remind the MGM container requires enough memory to store the namespace (actual requirements depend on the number of files and folders stored on EOS) and that the container folder `/var/eos` must be stored on persistent media -- It stores the namespace information.


#### b. EOS File Storage Server (FST)
Create multiple EOS File Storage Server (FST) -- **Note: At least two are required!** -- via the provided script `eos-storage-fst.sh`. This script will create yaml descriptors to deploy the FSTs. 
Usage:
```
bash eos-storage-fst.sh
Syntax:  eos-storage-fst.sh <fst_number> <eos_mgm_alias> <eos_mq_alias>
```

For example:
```
bash eos-storage-fst.sh 1 eos-mgm.boxed.svc.cluster.local eos-mgm.boxed.svc.cluster.local
```
will create the file `eos-storage-fst1.yaml`, allowing for the deployment of the first FST.
Additional FSTs can be created using the procedure with an increasing <fst_number> as parameter.
Adding FSTs to the EOS cluster allows to scale out the storage demands by attaching more and more volumes to the mass end storage service.

The yaml file for FSTs specifies a headless Kubernetes service, resulting in the ability to reach the FST server, e.g., at `eos-fst1.boxed.svc.cluster.local`.
The EOS-FST*N* container will run on a node labeled with `nodeApp=eos-fst*N*`.
The container folder `/mnt/fst_userdata` must be stored on persistent media -- It stores user data.


#### c. Finalize and verify deployment
Verify the container status via `kubectl`:
```
kubectl -n boxed get pods -o wide

NAME                             READY     STATUS    RESTARTS   AGE       IP               NODE
eos-fst5                         1/1       Running   0          18h       10.244.3.3       up2kube-fst5.cern.ch
eos-fst6                         1/1       Running   0          14d       10.244.12.21     up2kube-fst6.cern.ch
eos-fst7                         1/1       Running   0          14d       10.244.13.21     up2kube-fst7.cern.ch
eos-fst8                         1/1       Running   0          14d       10.244.14.21     up2kube-fst8.cern.ch
eos-mgm                          1/1       Running   0          18h       10.244.6.146     up2kube-mgm.cern.ch
ldap                             1/1       Running   1          37d       10.244.7.10      up2kube-ldap.cern.ch
```
In the above picture, one container with MGM functionalities is running and 4 FSTs containers are provided as file servers.

Now, get a shell in the MGM container:
`kubectl -n boxed exec -it eos-mgm bash`
 
Verify the EOS namespace:
```
[root@eos-mgm /]# eos ns 
# ------------------------------------------------------------------------------------
# Namespace Statistic
# ------------------------------------------------------------------------------------
ALL      Files                            40 [booted] (0s)
ALL      Directories                      124
# ....................................................................................
ALL      Compactification                 status=off waitstart=0 interval=0 ratio-file=0.0:1 ratio-dir=0.0:1
# ....................................................................................
ALL      Replication                      mode=master-rw state=master-rw master=eos-mgm.eos-mgm.boxed.svc.cluster.local configdir=/var/eos/config/eos-mgm.eos-mgm.boxed.svc.cluster.local/ config=default active=true
# ....................................................................................
ALL      File Changelog Size              206.02 kB
ALL      Dir  Changelog Size              15.49 MB
# ....................................................................................
ALL      avg. File Entry Size             5150 B
ALL      avg. Dir  Entry Size             124.95 kB
# ------------------------------------------------------------------------------------
ALL      files created since boot         0
ALL      container created since boot     0
# ------------------------------------------------------------------------------------
ALL      current file id                  106
ALL      current container id             135
# ------------------------------------------------------------------------------------
ALL      memory virtual                   816.05 MB
ALL      memory resident                  144.17 MB
ALL      memory share                     12.30 MB
ALL      memory growths                   342.13 MB
ALL      threads                          98
ALL      uptime                           66859
# ------------------------------------------------------------------------------------
```

Verify the nodes part of the EOS cluster:
```
[root@eos-mgm /]# eos node ls
┌──────────┬──────────────────────────────────────────────┬────────────────┬──────────┬────────────┬──────┬──────────┬────────┬────────┬────────────────┬─────┐
│type      │                                      hostport│          geotag│    status│      status│  txgw│ gw-queued│  gw-ntx│ gw-rate│  heartbeatdelta│ nofs│
└──────────┴──────────────────────────────────────────────┴────────────────┴──────────┴────────────┴──────┴──────────┴────────┴────────┴────────────────┴─────┘
 nodesview  eos-fst5.eos-fst5.boxed.svc.cluster.local:1095       eos-docker     online           on    off          0       10      120                2     1 
 nodesview  eos-fst6.eos-fst6.boxed.svc.cluster.local:1095       eos-docker     online           on    off          0       10      120                1     1 
 nodesview  eos-fst7.eos-fst7.boxed.svc.cluster.local:1095       eos-docker     online           on    off          0       10      120                1     1 
 nodesview  eos-fst8.eos-fst8.boxed.svc.cluster.local:1095       eos-docker     online           on    off          0       10      120                3     1 
```

Verify the filesystems attached to the nodes:
```
[root@eos-mgm /]# eos fs ls
┌─────────────────────────────────────────┬────┬──────┬────────────────────────────────┬────────────────┬────────────────┬────────────┬──────────────┬────────────┬────────┬────────────────┐
│host                                     │port│    id│                            path│      schedgroup│          geotag│        boot│  configstatus│       drain│  active│          health│
└─────────────────────────────────────────┴────┴──────┴────────────────────────────────┴────────────────┴────────────────┴────────────┴──────────────┴────────────┴────────┴────────────────┘
 eos-fst5.eos-fst5.boxed.svc.cluster.local 1095      5                /mnt/fst_userdata        default.0       eos-docker      booting             rw      nodrain   online      no smartctl 
 eos-fst6.eos-fst6.boxed.svc.cluster.local 1095      6                /mnt/fst_userdata        default.0       eos-docker      booting             rw      nodrain   online      no smartctl 
 eos-fst7.eos-fst7.boxed.svc.cluster.local 1095      7                /mnt/fst_userdata        default.0       eos-docker      booting             rw      nodrain   online      no smartctl 
 eos-fst8.eos-fst8.boxed.svc.cluster.local 1095      8                /mnt/fst_userdata        default.0       eos-docker      booting             rw      nodrain   online      no smartctl 
```

The *boot* column should report `booted` and the *configstatus* should be `rw`.



### 3. Deployment of CERNBox

The CERNBox service, composed of the Web interface ("cernbox"), the gateway ("cernboxgateway"), and the database backend ("cernboxmysql"), can be deployed by simply creating the resources described in `CERNBOX.yaml`. The three containers are deployed via resources of type Deployment.

Before proceeding with the deployment, please remind that:

- The container responsible for the Web interface ("cernbox") will be downloaded and executed on the node labeled with `nodeApp=cernbox` and the container path `/var/www/html/cernbox/data` must be stored on persistent media;
- In case of deployment with MySQL database backend, the MySQL container ("cernboxmysql") will run on the same node of "cernbox", i.e., the node with label `nodeApp=cernbox`. Container path `/var/lib/mysql` must be stored on persistent media;
- The container running the gateway process ("cernboxgateway") will be downloaded and executed on the node labeled with `nodeApp=cernbox-gateway` and requires access to the hostNetwork of the node.


#### Site-specific paramenters

Few configuration parameters are site-specific and require modifications to the `CERNBOX.yaml` file.
Consider changing, in the environment variable section:

1. For "cernbox", the envvar `CERNBOXGATEWAY_HOSTNAME` must match the Fully Qualified Domain Name (FQDN) of the node where the "cernboxgateway" container will execute. Please, adjust it accordingly to your DNS configuration.
2. For "cernboxgateway", the envvar `HOSTNAME` must match the FQDN of the node where the "cernboxgateway" container will execute. Please, adjust it accordingly to your DNS configuration.
3. For "cernboxgateway", the envvar `SWAN_BACKEND` must have a value matching the FQDN of the node where the "swan" container will execute (read more in "Deployment of SWAN" section). Please, adjust it accordingly to your DNS configuration. 
3b. Similarly, the envvar `SWAN_BACKEND_PORT` must be equal to the listening port of the JupyterHub service running in the "swan" container. The default setting is 443. If you modify the default settins, please adjust it consistently with your setup. 


#### Service internals parameters

It is possible to configure some of the service internals via environment variable switches:

1. For "cernbox", the envvar `AUTH_TYPE` can be set to "local" for login via LDAP credentials or to "shibboleth" for login via Single Sign-On and similar technologies. The provided configuration for shibboleth is compatible with CERN SSO and will require modifications to make it work with your SSO solution.
2. For "cernbox", the envvar `DATABASE_BACKEND` can be set to "SQLite" (so to use the SQLite backend integrated into the "cernbox" container) or to "MySQL" (so to use the external container "cernboxmysql"). The latter configuration is recommended for production-like deployments.
3. For "cernboxgateway", the envvar `HTTP_PORT` specifies the listening port for HTTP traffic. Same for `HTTPS_PORT` and HTTPS traffic. The default settings are ports 80 and 443, respectively.



### 4. Deployment of SWAN

The SWAN service, composed of JupyterHub ("swan"), the EOS fuse client ("eos-fuse"), and the CVMFS client ("cvmfs"), can be deployed by simply creating the resources described in `SWAN.yaml`.
The JupyterHub container is a resource of type Deployment, while the EOS fuse client and the CVMFS client are resources of type DaemonSet.

Before proceeding with the deployment, please remind that:

- The SWAN service requires at least one worker node where to run single-user's session. This node should be labeled as "nodeApp=swan-users". Adding more worker nodes provides the ability to scale out the capacity of the service according to the number of concurrent sessions it has to sustain. The EOS fuse client and the CVMFS client will be automatically deployed on all the nodes labeled as "nodeApp=swan-users";
- The container responsible for spawning, managing, and proxying multiple Jupyter sessions ("jupyterhub") will be downloaded and executed on the node labeled with `nodeApp=swan`, requires access to the hostNetwork of the node, and the container path `/srv/jupyterhub/jupyterhub_data` must be stored on persistent media.

Also, SWAN requires access to the Kubernetes cluster resources and the ability to list and start containers in the namespace where it is deployed.
In order to achieve this, please review your cluster configuration and, if needed, configure the default service account for the namespace as an admin of the cluster.

Example with namespace "boxed":
```
kubectl create clusterrolebinding add-on-cluster-admin --clusterrole=cluster-admin --serviceaccount=boxed:default
```


#### Site-specific paramenters

Few configuration parameters are site-specific and require modifications to the `SWAN.yaml` file.
Consider changing, in the environment variable section:

1. For "swan", the envvar `HOSTNAME` must match the FQDN of the node where the "jupyterhub" container will execute. Please, adjust it accordingly to your DNS configuration.


#### Service internals parameters

It is possible to configure some of the service internals via environment variables in `SWAN.yaml`:

1. For "swan", the envvar `CONTAINER_IMAGE` can be used to specify the base image for single-user's sessions;
2. For "swan", the envvars `NODE_SELECTOR_KEY` and `NODE_SELECTOR_VALUE` must match "nodeApp" and "swan-users", respectively. In case the label identifying SWAN worker nodes is modified, please update these two envvars consistently.
3. For "swan", the envvar `HTTP_PORT` specifies the listening port for HTTP traffic. Same for `HTTPS_PORT` and HTTPS traffic. The default setting are ports 80 and 443, respectively.





-----

## The Network Perspective

    WIP


-----

## The Storage Perspective

    WIP


### How to Fail Over a Node with Persistent Storage Attached

