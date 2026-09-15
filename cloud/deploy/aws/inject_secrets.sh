#!/bin/bash

# Questo script inietta i Secret (AWS e HPC) nel cluster K8s in Cloud usando il kubeconfig locale.
# Da lanciare SOLO DOPO aver eseguito "terraform apply" e "ansible-playbook setup_k8s_cluster.yml".

echo "Caricamento variabili (per HPC)..."
# Le carichiamo da .env (assumendo che sia nella root del progetto o in cloud/)
source ../../.env 2>/dev/null || source ../../../.env 2>/dev/null

echo "Configurazione AWS Credentials Secret..."
# Qui usiamo le credenziali AWS già configurate nel tuo ambiente locale
export AWS_ACCESS_KEY_ID=$(aws configure get default.aws_access_key_id)
export AWS_SECRET_ACCESS_KEY=$(aws configure get default.aws_secret_access_key)

kubectl --kubeconfig=kubeconfig delete secret aws-credentials --ignore-not-found
kubectl --kubeconfig=kubeconfig create secret generic aws-credentials \
  --from-literal=AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
  --from-literal=AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"

echo "Configurazione HPC Credentials Secret..."
# IMPORTANTE: la password per HPC presa dal .env
kubectl --kubeconfig=kubeconfig delete secret hpc-credentials --ignore-not-found
kubectl --kubeconfig=kubeconfig create secret generic hpc-credentials \
  --from-literal=CLUSTER_USER="${CLUSTER_USER}" \
  --from-literal=CLUSTER_HOST="${CLUSTER_HOST}" \
  --from-literal=CLUSTER_PW="${CLUSTER_PW}"

echo "Tutti i Secret sono stati iniettati con successo nel cluster Cloud!"
