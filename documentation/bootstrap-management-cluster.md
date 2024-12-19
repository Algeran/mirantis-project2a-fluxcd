# Bootstrap the management cluster

## Local kind cluster

To install simple and lightweight local kubernetes cluster, you can use [kind](https://kind.sigs.k8s.io/).

By default, the `0.25.0` kind version is instralled. You can specify another version with the `KIND_VERSION` environment variable.

To bootstrap the local kind cluster 

```
  make bootstrap-kind-cluster
```

Default cluster name is the `hmc-management-local`. It can be changed with the `KIND_CLUSTER_NAME` environment variable.


## k3s cluster

To test more production-ready cluster, you can install [k3s kubernetes cluster](https://k3s.io/). It can be installed locally (supported only for Linux OS) or
provision AWS infrastructure with terraform and install k3s cluster on top of it.

By default, it installs `v1.31.3+k3s1` k3s version. You can change it with the `K3S_CLUSTER_VERSION` variable. List of available releases can be found on [GitHub](https://github.com/k3s-io/k3s/releases).

### Local k3s installation

```
  make bootstrap-k3s
```

If you install k3s on the remote machine manually and to access it you can specify the public IP via `K3S_PUBLIC_IP_LB` variable.

### Provision AWS infrastructure and install k3s

1. Please make sure that AWS credentials are configured to provision infrastructure via terraform
2. create file `terraform/aws/cluster-infra/terraform.tfvars` and set variables:
    ```
    user = "your-unique-username" # it will be used to name resources
    region = "us-west-2" # AWS region where resources will be created
    ```
3. Provision infra and Bootstrap cluster
    ```
      make bootstrap-k3s-over-aws
    ```

