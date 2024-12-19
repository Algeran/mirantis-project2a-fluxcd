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
├── clusters            # 2A-managed clusters
│   ├── aws
|   ...
│   └── azure
│       
├── templates           # Custom ClusterTemplates and ServiceTemplates
│   ├── cluster
│   └── service
|   
├── credentials         # platform credentials (encrypted)
│   ├── aws
|   ...
│   └── azure
|
├── management                # management cluster configuration
│   ├── hmc-system
|   ...
│   └── sealed-secrets
│       
└── flux              # Flux CD configurations
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
    More details and other options can be found in the [documentation](./documentation/bootstrap-management-cluster.md).

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
    The 2A platofrm deploys various components under the hood including the `Management` object, so it's completely fine if the cluster will respond for a while that the management object is not found. When it's created, you need to wait until all 2a components are ready and have `true` value. The output should look like:
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
  
  5. TBD: Install Helm repo to the management cluster. It will be used to store helm charts with custom cluster and service templates
  
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
    make deploy-aws-standalone-0-0-4
    ```
    This command generates manifest for the ManagedCluster object, you can find it under the `clusters/aws/standalone-0.0.4.yaml` path in the GitOps repository.
    It uses AWS credential that was created on the previous steps and deploys simple standalone cluster with 1 control plane and 2 worker nodes

2. Monitor the deployment of the Cluster and wait until it be in READY `True` status:
    ```
    make watch-aws-standalone-0-0-4
    ```

3. Create Kubeconfig for Cluster:
    ```
    make get-kubeconfig-aws-standalone-0-0-4
    ````
    This will put a kubeconfig for a cluster admin under the folder `kubeconfigs`

4. Access Cluster through kubectl
    ```
    PATH=$PATH:./bin KUBECONFIG="./kubeconfigs/managed-standalone-aws-$USERNAME.kubeconfig" kubectl get no
    ```

    The output should be similar to:
    ```
    NAME                                               STATUS   ROLES           AGE   VERSION
    managed-standalone-aws-yourusername-cp-0             Ready    control-plane   47m   v1.31.1+k0s
    managed-standalone-aws-yourusername-md-cplv7-7qglt   Ready    <none>          45m   v1.31.1+k0s
    managed-standalone-aws-yourusername-md-cplv7-9tj24   Ready    <none>          45m   v1.31.1+k0s
    ```

## Demo 2: Install built-in ServiceTemplate into single Cluster

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
    make deploy-aws-standalone-0-0-4-ingress
    ```

    This patches the existing managed cluster manifest under the `clusters/aws/standalone-0.0.4.yaml` path in the GitOps repo with the built-int `ingress-nginx-4-11-0` service template. You can compare changes by checking the git history, the only difference should be a new block of code with services:

    ```
      services:
      - template: ingress-nginx-4-11-0
        name: ingress-nginx
        namespace: ingress-nginx
    ```

2. Check that ingress-nginx is installed in the managed cluster:
    ```
    PATH=$PATH:./bin KUBECONFIG="./kubeconfigs/managed-standalone-aws-$USERNAME.kubeconfig" kubectl get pods -n ingress-nginx
    ```

    The output should be similar to:
    ```
    NAME                                        READY   STATUS    RESTARTS   AGE
    ingress-nginx-controller-86bd747cf9-2dvfl   1/1     Running   0          12m
    ```
    
    You can also check the services status of the `ManagedCluster` of object in management cluster:

    ```
    PATH=$PATH:./bin kubectl -n hmc-system get managedcluster managed-standalone-aws-$USERNAME -o yaml
    ```

    The output under the `status.services` should contain information about successfully deployed ingress nginx service:

    ```
    ...
      services:
      - clusterName: managed-standalone-aws-yourusername
        clusterNamespace: hmc-system
        conditions:
        - lastTransitionTime: "2024-12-19T17:24:35Z"
          message: ""
          reason: Provisioned
          status: "True"
          type: Helm
        - lastTransitionTime: "2024-12-19T17:24:35Z"
          message: Release ingress-nginx/ingress-nginx
          reason: Managing
          status: "True"
          type: ingress-nginx.ingress-nginx/SveltosHelmReleaseReady
    ```

## Demo 3: Deploy clusters in different providers
## Demo 4: Install ServiceTemplate into multiple Cluster
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
