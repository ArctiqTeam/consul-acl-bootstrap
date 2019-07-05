# Consul ACL Bootstrap

This project is designed as a helper Kubernetes pod intended to be run following the deployment of Consul in a k8s cluster via the official Hashicorp Helm Chart [here](https://github.com/hashicorp/consul-helm). The primary goal of this project is to provide a more fully enterprise hardened deployment of Consul on Kubernetes by orchestrating the configuration of the ACL system as well as enable SSL ports in the Kubernetes deployments.

## Getting Started

In order to get started using this project a Consul deployment needs to be created in Kubernetes cluster preferrably using the official Consul Helm Chart.  If the chart isn't leveraged there are some configuration items required.  Technically speaking parts of the `bootstrap.sh` script in this project can also be used in a non-Kubernetes deployment, provided the configuration is completed in the same manner as the Helm Chart with the same requirements.

### Prerequisites

* A Consul cluster built via the official Consul Helm chart
* ACL system configured in Kubernetes via a custom secret created for the deployment with Helm called `acl-config` with the following configuration:

```hcl
      {
        "acl": {
          "enabled": true,
          "default_policy": "deny",
          "down_policy": "extend-cache",
          "enable_token_persistence": true
        }
      }
```

* SSL certificates configured and issued to the Helm chart deployment of Consul (this bootstrap also patches the Consul Statefulset and Daemonset to enable SSL)

### Installing

Once the requirements have been met, deploy the bootstrap job as follows:

```shell
kubectl create serviceaccount consul-acl-bootstrap -n consul

kubectl apply -f - <<EOF
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: consul-acl-bootstrap
  namespace: consul
rules:
- apiGroups: [""]
  resources:
    - secrets
  verbs: ["get", "create", "patch"]
- apiGroups:
  - apps
  resources:
    - statefulsets
  verbs: ["get", "patch"]
- apiGroups:
  - extensions
  resources:
    - daemonsets
  verbs: ["get", "patch"]
EOF

kubectl apply -f - <<EOF
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: consul-acl-bootstrap
  namespace: consul
subjects:
- kind: ServiceAccount
  name: consul-acl-bootstrap 
  namespace: consul 
roleRef:
  kind: Role
  name: consul-acl-bootstrap
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: consul-acl-bootstrap
  namespace: consul
spec:
  backoffLimit: 1
  activeDeadlineSeconds: 100
  template:
    spec:
      serviceAccountName: consul-acl-bootstrap
      containers:
      - name: consul-acl-bootstrap
        image: arctiqteam/consul-acl-bootstrap:2.2.1
        args:
          - "-n"
          - "consul"
          - "-s"
          - "arctiqtim-consul"
      restartPolicy: Never
EOF

# Use the following in order to retrieve the tokens for operator use etc ...

kubectl get secret acl-master-token -n $NAMESPACE -o json | jq -r '.data.token' | base64 -d
kubectl get secret acl-agent-token -n $NAMESPACE -o json | jq -r '.data.token' | base64 -d
```

In the job definition above customize the deployment with the arguments to provide a namespace for Consul in addition to the name of the deployment as configured in the Helm Chart.

## Authors

* **Tim Fairweather** - *Initial work* - [ArctiqTim](https://github.com/ArctiqTim)

## License

This project is licensed under the Mozilla Public 2.0 License - see the [LICENSE.md](LICENSE.md) file for details
