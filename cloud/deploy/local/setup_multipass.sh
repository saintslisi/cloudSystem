#!/bin/bash

# Configurazione Risorse
MASTER_CPU=2
MASTER_RAM="2G"
MASTER_DISK="10G"

WORKER1_CPU=2
WORKER1_RAM="2G"
WORKER1_DISK="15G"

WORKER2_CPU=4
WORKER2_RAM="4G"
WORKER2_DISK="20G" # Più grande per scaricare container e dati

# Il path reale della cartella data locale
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_PATH="../../../data"

set -e # Ferma lo script al primo errore

echo "============================================="
echo "🚀 Avvio Creazione Cluster K3s con Multipass"
echo "============================================="

# Controlla se multipass è installato
if command -v multipass &> /dev/null; then
    MULTIPASS_CMD="multipass"
elif [ -x "/snap/bin/multipass" ]; then
    MULTIPASS_CMD="/snap/bin/multipass"
else
    echo "❌ Errore: Multipass non è installato. Esegui 'sudo snap install multipass' prima di continuare."
    exit 1
fi

echo "🔄 Aggiornamento elenco immagini Multipass..."
$MULTIPASS_CMD find > /dev/null

echo "1️⃣ Creazione k3s-master..."
$MULTIPASS_CMD launch 22.04 --name k3s-master --cpus $MASTER_CPU --memory $MASTER_RAM --disk $MASTER_DISK --timeout 600
echo "✅ k3s-master creato!"

echo "2️⃣ Creazione k3s-worker-1 (Frontend/Backend)..."
$MULTIPASS_CMD launch 22.04 --name k3s-worker-1 --cpus $WORKER1_CPU --memory $WORKER1_RAM --disk $WORKER1_DISK --timeout 600
echo "✅ k3s-worker-1 creato!"

echo "3️⃣ Creazione k3s-worker-2 (AI Worker)..."
$MULTIPASS_CMD launch 22.04 --name k3s-worker-2 --cpus $WORKER2_CPU --memory $WORKER2_RAM --disk $WORKER2_DISK --timeout 600
echo "✅ k3s-worker-2 creato!"

echo "🔗 Montaggio della cartella data in k3s-worker-1 e k3s-worker-2..."
if [ -d "$DATA_PATH" ]; then
    $MULTIPASS_CMD mount "$DATA_PATH" k3s-worker-1:/app/data
    $MULTIPASS_CMD mount "$DATA_PATH" k3s-worker-2:/app/data
    echo "✅ Cartella montata con successo in entrambi i worker!"
else
    echo "⚠️ ATTENZIONE: La cartella $DATA_PATH non esiste. Creala e montala manualmente."
fi

echo "============================================="
echo "🌐 Recupero Indirizzi IP e Setup Ansible"
echo "============================================="

MASTER_IP=$($MULTIPASS_CMD info k3s-master | grep IPv4 | awk '{print $2}')
WORKER1_IP=$($MULTIPASS_CMD info k3s-worker-1 | grep IPv4 | awk '{print $2}')
WORKER2_IP=$($MULTIPASS_CMD info k3s-worker-2 | grep IPv4 | awk '{print $2}')

echo "k3s-master: $MASTER_IP"
echo "k3s-worker-1: $WORKER1_IP"
echo "k3s-worker-2: $WORKER2_IP"

CLOUD_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
# Creazione dell'inventario Ansible
mkdir -p "$CLOUD_DIR/ansible/inventory"
cat <<EOF > "$CLOUD_DIR/ansible/inventory/hosts.ini"
[master]
$MASTER_IP ansible_user=ubuntu ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[workers]
$WORKER1_IP ansible_user=ubuntu ansible_ssh_common_args='-o StrictHostKeyChecking=no'
$WORKER2_IP ansible_user=ubuntu ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[k3s_cluster:children]
master
workers
EOF

echo "✅ Inventario Ansible generato in ansible/inventory/hosts.ini!"

echo "🔑 Iniezione della chiave SSH utente (~/.ssh/id_rsa.pub) nelle VM per Ansible..."
if [ ! -f ~/.ssh/id_rsa.pub ]; then
    ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
fi
SSH_PUB_KEY=$(cat ~/.ssh/id_rsa.pub)
$MULTIPASS_CMD exec k3s-master -- bash -c "echo '$SSH_PUB_KEY' >> /home/ubuntu/.ssh/authorized_keys"
$MULTIPASS_CMD exec k3s-worker-1 -- bash -c "echo '$SSH_PUB_KEY' >> /home/ubuntu/.ssh/authorized_keys"
$MULTIPASS_CMD exec k3s-worker-2 -- bash -c "echo '$SSH_PUB_KEY' >> /home/ubuntu/.ssh/authorized_keys"

cat <<EOF > "$CLOUD_DIR/ansible/ansible.cfg"
[defaults]
inventory = inventory/hosts.ini
host_key_checking = False
private_key_file = ~/.ssh/id_rsa
EOF

echo "✅ File ansible.cfg creato e chiavi SSH configurate con successo!"
echo "🎉 Setup delle VM completato! Ora puoi lanciare i playbook Ansible."
