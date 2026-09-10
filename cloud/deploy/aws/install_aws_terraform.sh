#!/bin/bash
set -e

echo "🚀 Inizio installazione di AWS CLI v2 e Terraform..."

# Aggiornamento base
sudo apt update && sudo apt install -y curl unzip wget gnupg lsb-release

# --------------------------
# 1. Installazione AWS CLI
# --------------------------
echo "📦 Installazione AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install || sudo ./aws/install --update
rm -rf aws awscliv2.zip
echo "✅ AWS CLI installata con successo!"

# --------------------------
# 2. Installazione Terraform
# --------------------------
echo "📦 Installazione Terraform..."
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt update
sudo apt install -y terraform
echo "✅ Terraform installato con successo!"

echo "================================================="
echo "🎉 Installazione Completata!"
echo "Verifica AWS CLI:"
aws --version
echo "Verifica Terraform:"
terraform --version
echo "================================================="
