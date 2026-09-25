#!/bin/bash

# This script injects Secrets (AWS and HPC) into the K8s cluster on Cloud using the local kubeconfig.
# To be run ONLY AFTER running "terraform apply" and "ansible-playbook setup_k8s_cluster.yml".

echo "[*] Loading variables (for HPC)..."
# Loaded from .env (assuming it's in the project root or in cloud/)
source ../../.env 2>/dev/null || source ../../../.env 2>/dev/null

echo "[*] Configuring AWS Credentials Secret..."
# Using the AWS credentials already configured in your local environment
export AWS_ACCESS_KEY_ID=$(aws configure get default.aws_access_key_id)
export AWS_SECRET_ACCESS_KEY=$(aws configure get default.aws_secret_access_key)

kubectl --kubeconfig=kubeconfig delete secret aws-credentials --ignore-not-found
kubectl --kubeconfig=kubeconfig create secret generic aws-credentials \
  --from-literal=AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
  --from-literal=AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"

echo "[*] Configuring HPC Credentials Secret..."
# IMPORTANT: HPC password taken from .env
kubectl --kubeconfig=kubeconfig delete secret hpc-credentials --ignore-not-found
kubectl --kubeconfig=kubeconfig create secret generic hpc-credentials \
  --from-literal=CLUSTER_USER="${CLUSTER_USER}" \
  --from-literal=CLUSTER_HOST="${CLUSTER_HOST}" \
  --from-literal=CLUSTER_PW="${CLUSTER_PW}"

echo "[OK] All Secrets have been successfully injected into the Cloud cluster!"
