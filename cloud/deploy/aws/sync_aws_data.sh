#!/bin/bash
# Script per sincronizzare SOLO i dati strettamente necessari sui nodi AWS
# in modo da risparmiare tempo e costi di trasferimento.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/../../data"
KEY_FILE="$SCRIPT_DIR/terraform/k8s_key.pem"

if [ ! -f "$KEY_FILE" ]; then
    echo "Errore: Chiave SSH $KEY_FILE non trovata. Esegui terraform apply prima."
    exit 1
fi

chmod 400 "$KEY_FILE"

# Definisci i file strettamente necessari per far girare il frontend e il worker
# Non carichiamo l'intero dataset da decine di GB!
INCLUDES=(
    "models/fullset/"
    "models/subset/"
    "images/subset/"
    "images/imagesTest/"
    "sceneGraph/json/"
)

# Recupera gli IP dei nodi dall'inventory di Ansible
if [ ! -f "$SCRIPT_DIR/ansible/inventory/hosts.ini" ]; then
    echo "Errore: File hosts.ini non trovato. Esegui terraform apply per generarlo."
    exit 1
fi

MASTER_IP=$(grep -A 1 '\[master\]' "$SCRIPT_DIR/ansible/inventory/hosts.ini" | tail -n 1 | awk '{print $1}')
WORKER_IPS=$(grep -A 10 '\[workers\]' "$SCRIPT_DIR/ansible/inventory/hosts.ini" | grep -v '^\[' | grep -v '^$' | awk '{print $1}')

sync_to_node() {
    local NODE_IP=$1
    echo "======================================"
    echo "Sincronizzazione dati essenziali su nodo: $NODE_IP"
    echo "======================================"

    # Crea la directory di destinazione
    ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@$NODE_IP "sudo mkdir -p /app/data && sudo chown -R ubuntu:ubuntu /app/data"

    for path in "${INCLUDES[@]}"; do
        if [ -d "$DATA_DIR/$path" ]; then
            echo "Sincronizzazione $path ..."
            # Usa rsync per trasferire solo i dati necessari
            rsync -avz --progress -e "ssh -i $KEY_FILE -o StrictHostKeyChecking=no" "$DATA_DIR/$path" "ubuntu@$NODE_IP:/app/data/$path"
        else
            echo "Avviso: $DATA_DIR/$path non trovato in locale. Salto."
        fi
    done
    echo "Sincronizzazione su $NODE_IP completata!"
}

# Sincronizza sul Master
if [ ! -z "$MASTER_IP" ]; then
    sync_to_node "$MASTER_IP"
fi

# Sincronizza sui Workers
for WORKER_IP in $WORKER_IPS; do
    if [ ! -z "$WORKER_IP" ]; then
        sync_to_node "$WORKER_IP"
    fi
done

echo "Tutti i dati essenziali sono stati sincronizzati sui nodi AWS con successo!"
