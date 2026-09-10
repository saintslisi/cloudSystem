#!/bin/bash
echo "🔍 Ricerca del nuovo IP di k3s-master..."

MASTER_IP=$(multipass info k3s-master | grep IPv4 | awk '{print $2}')

if [ -z "$MASTER_IP" ]; then
    echo "❌ Errore: Non riesco a trovare l'IP di k3s-master. Le macchine sono accese? Usa 'multipass start --all'"
    exit 1
fi

echo "✅ Nuovo IP trovato: $MASTER_IP"

echo "🔄 Aggiornamento di kubeconfig..."
multipass exec k3s-master -- sudo cat /etc/rancher/k3s/k3s.yaml > kubeconfig
sed -i "s/127.0.0.1/$MASTER_IP/g" kubeconfig

echo "🔄 Aggiornamento del frontend con il nuovo IP del backend..."
sed -i -E "s|value: \"http://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:30080\"|value: \"http://$MASTER_IP:30080\"|g" k8s/frontend.yaml

echo "🚀 Riavvio del pod frontend per applicare le modifiche..."
KUBECONFIG=kubeconfig kubectl apply -f k8s/frontend.yaml > /dev/null

echo "====================================================="
echo "🎉 TUTTO PRONTO! Il cluster è configurato per il nuovo IP."
echo "👉 Apri il browser a questo indirizzo: http://$MASTER_IP:30173"
echo "====================================================="
