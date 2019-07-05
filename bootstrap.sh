#!/bin/bash
# author: Tim Fairweather
# email: tim.fairweather@arctiq.ca
# website: www.arctiq.ca

# This script is designed to be run inside of a kubernetes pod as a part of a job spec. The script requires some variable parameters to be passed to it as follows:
# usage: bootstrap.sh -n namespace -s fullname -p ssl_port

# Where namespace is the Kubernetes namespace where Consul is currently installed and fullname is the Name provided for the deployment via Helm, along with the SSL port.

# This bootstrap container is meant to run as a k8s job AFTER Consul has been deployed via the consul-helm project, with customizations to the deployment for acl config.

bootstrap ()
{
export ACL_MASTER_TOKEN=$(curl --request PUT http://$FULLNAME-server-0.$FULLNAME-server.$NAMESPACE.svc:8500/v1/acl/bootstrap | jq -r '.SecretID')

# Create Agent Role
curl \
  --request PUT \
  --header "X-Consul-Token: $ACL_MASTER_TOKEN" \
  --data \
'{
  "Name": "agent-tokens",
  "Rules": "node_prefix \"\" { policy = \"write\" } service_prefix \"\" { policy = \"read\" } agent_prefix \"\" { policy = \"write\" } session_prefix \"\" { policy = \"write\" }"
}' http://$FULLNAME-server-0.$FULLNAME-server.$NAMESPACE.svc:8500/v1/acl/policy
# Create Agent Token
export ACL_AGENT_TOKEN=$(curl \
  --request PUT \
  --header "X-Consul-Token: $ACL_MASTER_TOKEN" \
  --data \
'{
  "Description": "Agent Token",
  "Policies": [
      {
          "Name": "agent-tokens"
      }
  ]
}' http://$FULLNAME-server-0.$FULLNAME-server.$NAMESPACE.svc:8500/v1/acl/token | jq -r '.SecretID')

# Create Default Role
curl \
  --request PUT \
  --header "X-Consul-Token: $ACL_MASTER_TOKEN" \
  --data \
'{
  "Name": "default-tokens",
  "Rules": "node_prefix \"\" { policy = \"read\" } service_prefix \"\" { policy = \"read\" } query_prefix \"\" { policy = \"read\" }"
}' http://$FULLNAME-server-0.$FULLNAME-server.$NAMESPACE.svc:8500/v1/acl/policy
# Create Agent Token
export ACL_DEFAULT_TOKEN=$(curl \
  --request PUT \
  --header "X-Consul-Token: $ACL_MASTER_TOKEN" \
  --data \
'{
  "Description": "Default Token",
  "Policies": [
      {
          "Name": "default-tokens"
      }
  ]
}' http://$FULLNAME-server-0.$FULLNAME-server.$NAMESPACE.svc:8500/v1/acl/token | jq -r '.SecretID')

# Store the rendered tokens as k8s secrets
kubectl create secret generic acl-master-token --from-literal=token=${ACL_MASTER_TOKEN} -n $NAMESPACE --dry-run -o yaml | kubectl apply -f -
kubectl create secret generic acl-agent-token --from-literal=token=${ACL_AGENT_TOKEN} -n $NAMESPACE --dry-run -o yaml | kubectl apply -f -
kubectl create secret generic acl-default-token --from-literal=token=${ACL_DEFAULT_TOKEN} -n $NAMESPACE --dry-run -o yaml | kubectl apply -f -

# Update the agent configuration which is passed to the statefulset and daemonset
cd /tmp
cat <<EOF > acl_config.hcl
      {
        "acl": {
          "enabled": true,
          "default_policy": "deny",
          "down_policy": "extend-cache",
          "enable_token_persistence": true,
          "tokens": {
              "agent": "${ACL_AGENT_TOKEN}",
              "default": "${ACL_DEFAULT_TOKEN}"
          }
        }
      }
EOF
kubectl create secret generic acl-config --from-file=acl_config.hcl -n $NAMESPACE --dry-run -o yaml | kubectl apply -f -

## Issue with this routine is scaling the daemonset etc ...
# # Retrieve the POD IPs
# export POD_IPs=$(kubectl get pods -n consul  -l app=consul -o wide -o json | jq -r '.items | .[].status.podIP')

# # Apply the agent tokens
# for i in $POD_IPs
# do
#   curl \
#   --request PUT \
#   --header "X-Consul-Token: $ACL_MASTER_TOKEN" \
#   --data \
#   '{
#     "Token": "${ACL_AGENT_TOKEN}"
#   }' http://$i:8500/v1/agent/token/agent

#   curl \
#   --request PUT \
#   --header "X-Consul-Token: $ACL_MASTER_TOKEN" \
#   --data \
#   '{
#     "Token": "${ACL_DEFAULT_TOKEN}"
#   }' http://$i:8500/v1/agent/token/default

# done

# Trigger restart of all pods in the Consul namespace
# export FULLNAME="arctiqtim-consul"
# export NAMESPACE="consul"
# export PORT=8501
kubectl patch statefulset $FULLNAME-server -n $NAMESPACE -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"consul\",\"ports\":[{\"containerPort\":$PORT,\"name\":\"https\"}],\"env\":[{\"name\":\"CONSUL_HTTP_TOKEN\",\"valueFrom\":{\"secretKeyRef\":{\"key\":\"token\",\"name\":\"acl-agent-token\"}}}],\"volumeMounts\":[{\"mountPath\":\"/consul/userconfig/acl-agent-token\",\"name\":\"userconfig-agent-token\"}]}],\"volumes\":[{\"name\":\"userconfig-agent-token\",\"secret\":{\"secretName\":\"acl-agent-token\"}}]}}}}"
kubectl patch daemonset $FULLNAME -n $NAMESPACE -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"consul\",\"ports\":[{\"containerPort\":$PORT,\"hostPort\":$PORT,\"name\":\"https\"}],\"env\":[{\"name\":\"CONSUL_HTTP_TOKEN\",\"valueFrom\":{\"secretKeyRef\":{\"key\":\"token\",\"name\":\"acl-agent-token\"}}}],\"volumeMounts\":[{\"mountPath\":\"/consul/userconfig/acl-agent-token\",\"name\":\"userconfig-agent-token\"}]}],\"volumes\":[{\"name\":\"userconfig-agent-token\",\"secret\":{\"secretName\":\"acl-agent-token\"}}]}}}}"
kubectl patch service $FULLNAME-server -n $NAMESPACE -p "{\"spec\":{\"clusterIP\":\"None\",\"ports\":[{\"name\":\"https\",\"port\":$PORT,\"protocol\":\"TCP\",\"targetPort\":$PORT}]}}"
# kubectl patch statefulset $FULLNAME-server -n $NAMESPACE -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"date\":\"`date +'%s'`\"}}}}}"
# kubectl patch daemonset $FULLNAME -n $NAMESPACE -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"date\":\"`date +'%s'`\"}}}}}"
}

usage ()
{
    echo "usage: bootstrap.sh -n namespace -s fullname -p ssl_port"
}

while [ "$1" != "" ]; do
    case $1 in
        -n | --namespace )      shift
                                NAMESPACE=$1
                                ;;
        -s | --fullname )       shift
                                FULLNAME=$1
                                ;;
        -p | --port )           shift
                                PORT=$1
                                ;;
        -h | --help )           usage
                                exit
                                ;;
        * )                     usage
                                exit 1
    esac
    shift
done

while [ "$3" != "" ]; do
    case $3 in
        -n | --namespace )      shift
                                NAMESPACE=$3
                                ;;
        -s | --fullname )       shift
                                FULLNAME=$3
                                ;;
        -p | --port )           shift
                                PORT=$3
                                ;;
        -h | --help )           usage
                                exit
                                ;;
        * )                     usage
                                exit 1
    esac
    shift
done

while [ "$5" != "" ]; do
    case $5 in
        -n | --namespace )      shift
                                NAMESPACE=$5
                                ;;
        -s | --fullname )       shift
                                FULLNAME=$5
                                ;;
        -p | --port )           shift
                                PORT=$5
                                ;;
        -h | --help )           usage
                                exit
                                ;;
        * )                     usage
                                exit 1
    esac
    shift
done

# echo "Namespace is: $NAMESPACE"
# echo "Fullname is: $FULLNAME"

if [ "$NAMESPACE" ] && [ "$FULLNAME" ] && [ "$PORT" ]; then
  sleep 30
  bootstrap
else
  usage
  exit 1
fi
