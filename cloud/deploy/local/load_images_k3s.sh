#!/bin/bash
set -e

echo "[*] 1. Building local Docker images..."
docker build -t backend:latest ../../backend
docker build -t frontend:latest ../../frontend
docker build -t worker:latest -f ../../workerAI/Dockerfile ../../../

IMAGE_TAR="/home/santi/project-images-k3s.tar"

echo "[*] 2. Exporting images to a tar file..."
docker save backend:latest frontend:latest worker:latest -o "$IMAGE_TAR"
chmod 644 "$IMAGE_TAR"

echo "[+] 3. Transferring and loading to k3s-worker-1 (Frontend and Backend)..."
/snap/bin/multipass transfer "$IMAGE_TAR" k3s-worker-1:
/snap/bin/multipass exec k3s-worker-1 -- sudo k3s ctr images import project-images-k3s.tar
/snap/bin/multipass exec k3s-worker-1 -- rm project-images-k3s.tar

echo "[+] 4. Transferring and loading to k3s-worker-2 (AI Worker)..."
/snap/bin/multipass transfer "$IMAGE_TAR" k3s-worker-2:
/snap/bin/multipass exec k3s-worker-2 -- sudo k3s ctr images import project-images-k3s.tar
/snap/bin/multipass exec k3s-worker-2 -- rm project-images-k3s.tar

echo "[*] 5. Cleaning up temporary files..."
rm -f "$IMAGE_TAR"

echo "[OK] All images successfully loaded into the K3s cluster!"
