#!/bin/bash
echo "[*] Searching for the new IP of k3s-master..."

MASTER_IP=$(multipass info k3s-master | grep IPv4 | awk '{print $2}')

if [ -z "$MASTER_IP" ]; then
    echo "[ERROR] Cannot find the IP of k3s-master. Are the VMs running? Use 'multipass start --all'"
    exit 1
fi

echo "[OK] New IP found: $MASTER_IP"

echo "[*] Updating kubeconfig..."
multipass exec k3s-master -- sudo cat /etc/rancher/k3s/k3s.yaml > kubeconfig
sed -i "s/127.0.0.1/$MASTER_IP/g" kubeconfig

echo "[*] Updating frontend with the new backend IP..."
sed -i -E "s|value: \"http://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:30080\"|value: \"http://$MASTER_IP:30080\"|g" k8s/frontend.yaml

echo "[+] Restarting frontend pod to apply changes..."
KUBECONFIG=kubeconfig kubectl apply -f k8s/frontend.yaml > /dev/null

echo "====================================================="
echo "[OK] ALL SET! The cluster is configured for the new IP."
echo " Open your browser at this address: http://$MASTER_IP:30173"
echo "====================================================="
