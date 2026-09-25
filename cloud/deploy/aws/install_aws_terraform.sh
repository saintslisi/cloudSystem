#!/bin/bash
set -e

echo "[*] Starting installation of AWS CLI v2 and Terraform..."

# Base update
sudo apt update && sudo apt install -y curl unzip wget gnupg lsb-release

# --------------------------
# 1. Install AWS CLI
# --------------------------
echo "[*] Installing AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install || sudo ./aws/install --update
rm -rf aws awscliv2.zip
echo "[OK] AWS CLI successfully installed!"

# --------------------------
# 2. Install Terraform
# --------------------------
echo "[*] Installing Terraform..."
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt update
sudo apt install -y terraform
echo "[OK] Terraform successfully installed!"

echo "================================================="
echo "🎉 Installazione Completata!"
echo "Verifica AWS CLI:"
aws --version
echo "Verifica Terraform:"
terraform --version
echo "================================================="
