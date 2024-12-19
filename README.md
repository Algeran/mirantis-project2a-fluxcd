# Example of Mirantis HMC operator (Project 2A) usage with Flux CD

## Prerequisites

1. Create the fresh GitHub repository, it will be used to store and sync the management cluster state via Flux CD
2. Create [GitHub PAT](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) token that will be used by Flux to connect to the GitHub repository and sync the state
3. Make sure that Docker is installed on your machine. It's required to bootstrap and run local kind cluster.
4. Set environment variables:
    ```
    export GITHUB_TOKEN=<gh-pat-token>
    export GITHUB_USERNAME=<your-gh-username>
    export GITHUB_REPO_NAME=<gitops-gh-repository-name>
    export USERNAME=<your-username>
    ```
    Variable `USERNAME` is required for managed clusters deployment steps and is used to ensure that created resources are not conflict if more than one user try to run this demo in the same cloud account

## Produced GitOps repo structure

```
/
├── clusters                                            # 2A-managed clusters
│   ├── aws
|   │   ├── patches                                     # Patches for managed clusters (e.g. ClusterTemplate version)
|   |   │   ├── builtin-standaline-0.0.4.yaml
|   |   │   ...
|   |   │   └── custom-cluster-configuration-0.0.1.yaml
|   │   ├── managed-builtin-standalone-aws.yaml
|   │   ...
|   │   ├── managed-custom-eks.yaml
|   │   └── kustomization.yaml
│   ├── azure                                           # Internal structure similar to aws
│   ...
│   ├── services                                        # Patches with beach-head services for managed clusters
│   └── kustomization.yaml                              # Main kustomization file to build ManagedCluster manifests
│
├── services                                            # 2A-managed multi-cluster beach-head services
│   ├── ingress
|   ...
│   └── kyverno       
│
├── templates                                           # Custom ClusterTemplates and ServiceTemplates
│   ├── cluster
│   └── service
|   
├── credentials                                         # Platform credentials (encrypted)
│   ├── aws
|   ...
│   └── azure
|
├── management                                          # Management cluster configuration
│   ├── hmc-system
|   ...
│   └── sealed-secrets
│       
└── flux                                                # Flux CD configurations
    └── management
        ├── flux-system     
        ...
        └── hmc-system.yaml
```


## General setup

1. Create management cluster. The following command will deploy the simple local kubernetes cluster with kind.  
    ```
    make bootstrap-kind-cluster
    ```
    More details can be found in the [documentation](./documentation/1-general-setup-bootstrap-kind-cluster.md).

2. Install flux ([official documentation](https://fluxcd.io/flux/installation/bootstrap/github/)).  
    ```
    make bootstrap-flux
    ```
    In this tutorial the [GitHub repo](https://fluxcd.io/flux/installation/bootstrap/github/) insallation is used.

3. Deploy 2A into management cluster:
    ```
    make bootstrap-hmc-operator
    ```
4. Monitor the installation of 2A:
    ```
    PATH=$PATH:./bin kubectl get management hmc -o go-template='{{range $key, $value := .status.components}}{{$key}}: {{if $value.success}}{{$value.success}}{{else}}{{$value.error}}{{end}}{{"\n"}}{{end}}'
    ```
    The 2A platofrm deploys various components under the hood including the `Management` object, so it's completely fine if the cluster will respond for a while that the Management object is not found. When it's created, you need to wait until all 2a components are ready and have `true` value. The output should look like:
    ```
    capi: true
    cluster-api-provider-aws: true
    cluster-api-provider-azure: true
    cluster-api-provider-vsphere: true
    hmc: true
    k0smotron: true
    projectsveltos: true
    ```
    To get more information about 2A components, please visit the [official documentation](https://mirantis.github.io/project-2a-docs/).
  
5. Install the Demo Helm Repo into 2A:
    ```
    make setup-helmrepo
    ```
    This step deploys simple local OCI Helm registry and adds a [`HelmRepository` resource](https://fluxcd.io/flux/components/source/helmrepositories/) to the cluster that contains Helm charts for this demo.

    It also packages and pushes Helm charts from the `charts` directory - custom cluster and service configurations that will be used in Demos.

    Check that Helm registry is installed:
    ```shell
    PATH=$PATH:./bin kubectl -n hmc-system get po helm-registry
    ```
    Result example:
    ```
    NAME            READY   STATUS    RESTARTS   AGE
    helm-registry   1/1     Running   0          3m9s
    ```

    And Flux HelmRepository object registered
    ```shell
    PATH=$PATH:./bin kubectl -n hmc-system get helmrepo 2a-demos
    ```
    Result example:
    ```
    NAME       URL                                    AGE     READY   STATUS
    2a-demos   oci://helm-registry:5000/helm-charts   2m25s
    ```

  
## Infra setup

Since we need to store the state of the management cluster in a git repository and we will need to create configurations with sensitive data (credentials for AWS, Azure, etc), for this demo we will install [kubeseal](https://fluxcd.io/flux/guides/sealed-secrets/) in the cluster that will help store secrets in a public repository securely.
    ```
    make install-kubeseal
    ```
    As a result, it will install the kubeseal operator and then fetch to the `.kubeseal` directory the certificate that should be used to encrypt secrets.

As next you need to decide into which infrastructure you would like to install the Demo clusters. This Demo Repo has support for the following Infra Providers (more to follow in the future):
  - AWS

### AWS Setup

This assumes that you already have configured the required [AWS IAM Roles](https://mirantis.github.io/project-2a-docs/quick-start/aws/#configure-aws-iam) and an [AWS account with the required permissions](https://mirantis.github.io/project-2a-docs/quick-start/aws/#step-1-create-aws-iam-user).

1. Export AWS keys as environment variables:
    ```
    export AWS_ACCESS_KEY_ID="<aws-access-key>"
    export AWS_SECRET_ACCESS_KEY="<aws-secret-key>"
    ```

2. Create credentials
    ```
    make setup-aws-creds
    ```

    This command will create sealed secret with AWS creds and AWS cluster identity + credentials in the management cluster.
  
3. Check that credentials are ready to use
    ```
    PATH=$PATH:./bin kubectl -n hmc-system get credentials aws-credential
    ```
    The output should be similar to:
    ```
    NAME             READY   DESCRIPTION
    aws-credential   true    Basic AWS credentials
    ```

### Azure Setup

This assumes that you already have configured the required [Azure providers](https://mirantis.github.io/project-2a-docs/quick-start/azure/#register-resource-providers) and created a [Azure Service Principal](https://mirantis.github.io/project-2a-docs/quick-start/azure/#step-2-create-a-service-principal-sp).

1. Export Azure Service Principal keys as environment variables:
    ```
    export AZURE_SP_PASSWORD=<Service Principal password>
    export AZURE_SP_APP_ID=<Service Principal App ID>
    export AZURE_SP_TENANT_ID=<Service Principal Tenant ID>
    ```

2. Create credentials
    ```
    make setup-azure-creds
    ```

    This command will create sealed secret with Azure creds and Azure cluster identity + credentials in the management cluster.
  
3. Check that credentials are ready to use
    ```
    PATH=$PATH:./bin kubectl -n hmc-system get credentials azure-credential
    ```
    The output should be similar to:
    ```
    NAME               READY   DESCRIPTION
    azure-credential   true    Basic Azure credentials
    ```


# Demo 1: Single standalone cluster deployment from the built-in ClusterTemplate

This demo show how a simple standalone cluster from built-in cluster templates can be created in the `hmc-system` namespace. It does not require any additional users in k8s or namespaces to be installed.

In the real world this would most probably be done by a Platform Team Lead that has admin access to the Management Cluster in order to create a test cluster from a new ClusterTemplate without the expectation for this cluster to exist for a long time.

You can browse built-in managed cluster templates with the command:
```
PATH=$PATH:./bin kubectl -n hmc-system get clustertemplates
```

The output should be similar to:
```
NAME                          VALID
aws-eks-0-0-2                 true
aws-hosted-cp-0-0-3           true
aws-standalone-cp-0-0-4       true
azure-hosted-cp-0-0-3         true
azure-standalone-cp-0-0-4     true
vsphere-hosted-cp-0-0-3       true
vsphere-standalone-cp-0-0-3   true
```

1. Install Test Cluster:
    ```
    make deploy-builtin-aws-standalone
    ```
    This command generates manifest for the ManagedCluster object, you can find it under the `clusters/aws/builtin-standalone-0.0.4.yaml` path in the GitOps repository.
    It uses AWS credential that was created on the previous steps and deploys simple standalone cluster with 1 control plane and 2 worker nodes

2. Monitor the deployment of the Cluster and wait until it be in READY `True` status:
    ```
    make watch-builtin-aws-standalone
    ```

3. Create Kubeconfig for Cluster:
    ```
    make get-kubeconfig-builtin-aws-standalone
    ````
    This will put a kubeconfig for a cluster admin under the folder `kubeconfigs`

4. Access Cluster through kubectl
    ```
    PATH=$PATH:./bin KUBECONFIG="./kubeconfigs/managed-builtin-standalone-aws-$USERNAME.kubeconfig" kubectl get no
    ```

    The output should be similar to:
    ```
    NAME                                               STATUS   ROLES           AGE   VERSION
    managed-standalone-aws-yourusername-cp-0             Ready    control-plane   47m   v1.31.1+k0s
    managed-standalone-aws-yourusername-md-cplv7-7qglt   Ready    <none>          45m   v1.31.1+k0s
    managed-standalone-aws-yourusername-md-cplv7-9tj24   Ready    <none>          45m   v1.31.1+k0s
    ```

## Demo 2: Install built-in ServiceTemplate into single Cluster

**This expects `Demo 1` to be completed**

This demo shows how a ServiceTemplate can be installed in a Cluster. In this demo we use the built-in ServiceTemplate for ingress controller. You can browse all built-in service templates with the command:
```
PATH=$PATH:./bin kubectl -n hmc-system get servicetemplates
```

The output should be similar to:
```
NAME                   VALID
ingress-nginx-4-11-0   true
ingress-nginx-4-11-3   true
kyverno-3-2-6          true
```

1. Patch managed cluster with built-in ingress-controller service:
    ```
    make deploy-builtin-aws-standalone-ingress
    ```

    It adds the patch with the built-int `ingress-nginx-4-11-0` service template and labels the existing managed cluster under `clusters/aws/managed-builtin-standalone-aws.yaml` path in the GitOps repo. To review full change list, please check the latest commit.

2. Check that ingress-nginx is installed in the managed cluster:
    ```
    PATH=$PATH:./bin KUBECONFIG="./kubeconfigs/managed-builtin-standalone-aws-$USERNAME.kubeconfig" kubectl get pods -n ingress-nginx
    ```

    The output should be similar to:
    ```
    NAME                                        READY   STATUS    RESTARTS   AGE
    ingress-nginx-controller-86bd747cf9-2dvfl   1/1     Running   0          12m
    ```
    
    You can also check the services status of the `ManagedCluster` of object in management cluster:

    ```
    PATH=$PATH:./bin kubectl -n hmc-system get managedcluster managed-builtin-standalone-aws-$USERNAME -o yaml
    ```

    The output under the `status.services` should contain information about successfully deployed ingress nginx service:

    ```
    ...
      services:
      - clusterName: managed-standalone-aws-yourusername
        clusterNamespace: hmc-system
        conditions:
        ...
        - lastTransitionTime: "2024-12-19T17:24:35Z"
          message: Release ingress-nginx/ingress-nginx
          reason: Managing
          status: "True"
          type: ingress-nginx.ingress-nginx/SveltosHelmReleaseReady
    ```

## Demo 3: Deploy clusters in different providers

**Please make sure you configured Azure credentials!**

This demo shows how to deploy Azure managed cluster to demonstrate possibility to manage cluster deployments in various providers from the single management cluster. The built-in managed cluster templates is used as in Demo 1.

You can browse built-in managed cluster templates with the command:
```
PATH=$PATH:./bin kubectl -n hmc-system get clustertemplates
```

The output should be similar to:
```
NAME                          VALID
aws-eks-0-0-2                 true
aws-hosted-cp-0-0-3           true
aws-standalone-cp-0-0-4       true
azure-hosted-cp-0-0-3         true
azure-standalone-cp-0-0-4     true
vsphere-hosted-cp-0-0-3       true
vsphere-standalone-cp-0-0-3   true
```

1. Export Azure subscription ID environment variable - it's required to configure ManagedCluster object:
    ```
    export AZURE_SUBSCRIPTION_ID=<Azure subscription ID>
    ```
2. Install Test Cluster:
    ```shell
    make deploy-builtin-azure-standalone
    ```
    This command generates manifest for the ManagedCluster object, you can find it under the `clusters/azure/builtin-standalone-0.0.4.yaml` path in the GitOps repository.
    It uses Azure credential that was created on previous steps and deploys simple standalone cluster with 1 control plane and 2 worker nodes

2. Monitor the deployment of the Cluster and wait until it be in READY `True` status:
    ```shell
    make watch-builtin-azure-standalone
    ```

3. Create Kubeconfig for Cluster:
    ```shell
    make get-kubeconfig-builtin-azure-standalone
    ```
    This will put a kubeconfig for a cluster admin under the folder `kubeconfigs`

4. Access Cluster through kubectl
    ```shell
    PATH=$PATH:./bin KUBECONFIG="./kubeconfigs/managed-builtin-standalone-azure-$USERNAME.kubeconfig" kubectl get no
    ```

    The output should be similar to:
    ```
    NAME                                               STATUS   ROLES           AGE   VERSION
    managed-builtin-standalone-azure-yivchenkov-cp-0             Ready    control-plane   3m51s   v1.31.1+k0s
    managed-builtin-standalone-azure-yivchenkov-md-bx76c-4jbqr   Ready    <none>          2m13s   v1.31.1+k0s
    managed-builtin-standalone-azure-yivchenkov-md-bx76c-9z29s   Ready    <none>          2m14s   v1.31.1+k0s
    ```


## Demo 4: Install ServiceTemplate into multiple Cluster

**This expects at least `Demo 1` and/or `Demo 3` to be completed**

This Demo shows the capability of 2A to install a ServiceTemplate into multiple Clusters without the need to reference it in every cluster as we did in `Demo 2`.

While this demo can be shown even if you only have a single cluster, its obviously better to be demoed with two clusters. If you followed along the demo process you should have two clusters.

Be aware though that the cluster creation takes around 10-15mins, so depending on how fast you give the demo, the cluster creation might not be completed and the installation of services possible also delayed. You can totally follow this demo and the services will be installed after the clusters are ready.

This will install a `hmc.mirantis.com/v1alpha1/MultiClusterService` cluster-wide object to the management cluster. It has a clusterSelector configuration of the label `app.kubernetes.io/managed-by: Helm` which selects all `cluster.x-k8s.io/v1beta1/Cluster` objects with this label. Please, don't confuse `hmc.mirantis.com/v1alpha1/ManagedCluster` and `cluster.x-k8s.io/v1beta1/Cluster` types. First one - is the type of Project 2A objects, we deploy them to the management cluster and then, 2A operator creates various objects, including CAPI `cluster.x-k8s.io/v1beta1/Cluster`. `hmc.mirantis.com/v1alpha1/MultiClusterService` relies on `cluster.x-k8s.io/v1beta1/Cluster` labels. Currently, it's not possible to specify them in the `ManagedCluster` object configuration, there is an [issue](https://github.com/Mirantis/hmc/issues/801) on GitHub. But, to demonostrate the possibility of deploying service to multiple clusters without specifiying in each `ManagedCluster` object, we will use in this demo the `app.kubernetes.io/managed-by: Helm` label, which is automatically set to all `cluster.x-k8s.io/v1beta1/Cluster` objects by 2A.

1. Apply [`MultiClusterService`](https://mirantis.github.io/project-2a-docs/usage/create-multiclusterservice/) to cluster:
    ```shell
    make deploy-global-kyverno
    ```

2. After Flux CD reconciles the `MultiClusterService` object to the management cluster, check the deployment status:
    ```shell
    PATH=$PATH:./bin kubectl get multiclusterservice global-kyverno -o yaml
    ```

    In the output you can find information about clusters where the service is deployed:
    ```
    apiVersion: hmc.mirantis.com/v1alpha1
    kind: MultiClusterService
    ...
    status:
      ...
      services:
      - clusterName: managed-builtin-standalone-aws-youusername
        clusterNamespace: hmc-system
        conditions:
        - lastTransitionTime: "2024-12-30T15:11:57Z"
          message: ""
          reason: Provisioned
          status: "True"
          type: Helm
        - lastTransitionTime: "2024-12-30T15:11:57Z"
          message: Release kyverno/kyverno
          reason: Managing
          status: "True"
          type: kyverno.kyverno/SveltosHelmReleaseReady
      - clusterName: managed-builtin-standalone-azure-youusername
        clusterNamespace: hmc-system
        conditions:
        - lastTransitionTime: "2024-12-30T15:11:57Z"
          message: ""
          reason: Provisioned
          status: "True"
          type: Helm
        - lastTransitionTime: "2024-12-30T15:11:57Z"
          message: Release kyverno/kyverno
          reason: Managing
          status: "True"
          type: kyverno.kyverno/SveltosHelmReleaseReady
    ```

3. Check that kyverno is being installed in the two managed cluster:
    ```shell
    PATH=$PATH:./bin KUBECONFIG="./kubeconfigs/managed-builtin-standalone-aws-$USERNAME.kubeconfig" kubectl -n kyverno get po
    ```

    ```shell
    PATH=$PATH:./bin KUBECONFIG="./kubeconfigs/managed-builtin-standalone-azure-$USERNAME.kubeconfig" kubectl -n kyverno get po
    ```

    There might be a couple of seconds delay before that 2A and sveltos needs to start the installation of kyverno, give it at least 1 mins.


## Demo 5: Create custom ClusterTemplate and deploy managed cluster
## Demo 6: Create custom ServiceTemplate and deploy to managed cluster
## Demo 7: Single Standalone Cluster Upgrade
## Demo 8: Upgrade service in standalone cluster
## Demo 9: Upgrade service in multiple clusters
## Demo 10: Approve ClusterTemplate & InfraCredentials for separate Namespace
## Demo 11: Use approved ClusterTemplate in separate Namespace
## Demo 12: Test new clusterTemplate as 2A Admin, then approve them in separate Namespace
## Demo 13: Approve ServiceTemplate in separate Namespace
## Demo 14: Use ServiceTemplate in separate Namespace
