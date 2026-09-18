#!/bin/bash
set -e

# Colori per logging
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}   DEPLOYMENT AUTOMATIZZATO SISTEMI CLOUD   ${NC}"
echo -e "${GREEN}==============================================${NC}"

if [ ! -f "project_config.env" ]; then
    echo -e "${RED}[ERROR] File project_config.env non trovato! Copia il template e compilalo.${NC}"
    exit 1
fi

source project_config.env

echo -e "${YELLOW}1. Provisioning Infrastruttura AWS (Terraform)...${NC}"
cd cloud/deploy/aws/terraform
terraform apply -auto-approve

echo -e "${YELLOW}2. Estrazione IP per Ansible...${NC}"
MASTER_IP=$(terraform output -raw master_ip)
MASTER_PRIV_IP=$(terraform output -raw master_private_ip)
WORKER1_IP=$(terraform output -raw worker_1_ip)
WORKER2_IP=$(terraform output -raw worker_2_ip)

cd ../ansible
echo -e "${YELLOW}3. Aggiornamento automatico file inventory/hosts.ini...${NC}"
cat <<EOF > inventory/hosts.ini
[master]
$MASTER_IP ansible_user=ubuntu ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ServerAliveInterval=60' private_ip=$MASTER_PRIV_IP

[workers]
$WORKER1_IP ansible_user=ubuntu ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ServerAliveInterval=60'
$WORKER2_IP ansible_user=ubuntu ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ServerAliveInterval=60'

[k3s_cluster:children]
master
workers
EOF
cd ../../../..

echo -e "${YELLOW}4. Caricamento Secret su GitHub (HPC e AWS)...${NC}"
# Setup chiave SSH creata da terraform
gh secret set EC2_SSH_KEY < cloud/deploy/aws/terraform/k8s_key.pem --repo $GITHUB_REPO_NAME
gh secret set EC2_HOST --body "$MASTER_IP" --repo $GITHUB_REPO_NAME

# Setup credenziali HPC
gh secret set HPC_CLUSTER_USER --body "$CLUSTER_USER" --repo $GITHUB_REPO_NAME
gh secret set HPC_CLUSTER_HOST --body "$CLUSTER_HOST" --repo $GITHUB_REPO_NAME
gh secret set HPC_CLUSTER_PW --body "$CLUSTER_PW" --repo $GITHUB_REPO_NAME

# Recupero chiavi AWS se non settate nell'ambiente
if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)
fi
if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key)
fi

# Setup credenziali AWS per il Backend
gh secret set AWS_ACCESS_KEY_ID --body "$AWS_ACCESS_KEY_ID" --repo $GITHUB_REPO_NAME
gh secret set AWS_SECRET_ACCESS_KEY --body "$AWS_SECRET_ACCESS_KEY" --repo $GITHUB_REPO_NAME


echo -e "${YELLOW}5. Sincronizzazione Dati Pesanti (.pt, FAISS, Immagini) su S3 da locale...${NC}"
if [ -n "$LOCAL_DATA_DIR" ]; then
    echo "Sincronizzazione FAISS (Indici)..."
    aws s3 sync "$LOCAL_DATA_DIR/models/fullset/faiss" "s3://$AWS_S3_BUCKET_NAME/models/fullset/faiss" --exclude "*.gitkeep"
    
    echo "Sincronizzazione Checkpoints (Modelli addestrati)..."
    aws s3 sync "$LOCAL_DATA_DIR/models/fullset/checkpoints" "s3://$AWS_S3_BUCKET_NAME/models/fullset/checkpoints" --exclude "*.gitkeep"
    
    echo "Sincronizzazione Modelli Baseline e Tensori (.pt)..."
    aws s3 sync "$LOCAL_DATA_DIR/models/fullset/baseline" "s3://$AWS_S3_BUCKET_NAME/models/fullset/baseline" --exclude "*.gitkeep"
    
    echo "Sincronizzazione Modelli Semantic Web (GCN e Tensori)..."
    aws s3 sync "$LOCAL_DATA_DIR/models/fullset/semantic_web" "s3://$AWS_S3_BUCKET_NAME/models/fullset/semantic_web" --exclude "*.gitkeep"
    
    echo "Sincronizzazione Immagini di Test (imagesTest)..."
    aws s3 sync "$LOCAL_DATA_DIR/images/fullset/Test" "s3://$AWS_S3_BUCKET_NAME/images/fullset/Test" --exclude "*.gitkeep"
    
    echo "Sincronizzazione Immagini per il VectorDB (VectorDB)..."
    aws s3 sync "$LOCAL_DATA_DIR/images/fullset/VectorDB" "s3://$AWS_S3_BUCKET_NAME/images/fullset/VectorDB" --exclude "*.gitkeep"
    
    echo "Sincronizzazione Test Queries Scene Graphs (.pt)..."
    aws s3 cp "$LOCAL_DATA_DIR/sceneGraph/fullset/semantic/embedded/test_queries_scene_graphs.pt" "s3://$AWS_S3_BUCKET_NAME/sceneGraph/fullset/semantic/embedded/test_queries_scene_graphs.pt"
    
    echo "Sincronizzazione Test Gallery Scene Graphs (.pt) [Embeddings]..."
    
    echo "Sincronizzazione Scene Graphs Raw (.pt)..."
    aws s3 cp "$LOCAL_DATA_DIR/sceneGraph/fullset/semantic/raw/test_queries_scene_graphs.pt" "s3://$AWS_S3_BUCKET_NAME/sceneGraph/fullset/semantic/raw/test_queries_scene_graphs.pt"
    aws s3 cp "$LOCAL_DATA_DIR/sceneGraph/fullset/semantic/raw/test_gallery_scene_graphs.pt" "s3://$AWS_S3_BUCKET_NAME/sceneGraph/fullset/semantic/raw/test_gallery_scene_graphs.pt"
else
    echo -e "${RED}[WARNING] LOCAL_DATA_DIR non impostato, salto S3 sync.${NC}"
fi

echo -e "${YELLOW}6. Push delle modifiche infrastrutturali su Git...${NC}"
git add cloud/deploy/aws/ansible/inventory/hosts.ini
if ! git diff-index --quiet HEAD; then
    git commit -m "chore(infra): auto-update Ansible hosts.ini via deploy script"
    git push origin main
else
    echo "Nessuna modifica a hosts.ini da pusciare."
fi

echo -e "${YELLOW}7. Trigger della Master Pipeline GitHub Action...${NC}"
gh workflow run master-pipeline.yml --repo $GITHUB_REPO_NAME

echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}   TUTTO INIZIATO CON SUCCESSO!               ${NC}"
echo -e "${GREEN}   Controlla la repository GitHub per vedere  ${NC}"
echo -e "${GREEN}   lo stato del deployment!                   ${NC}"
echo -e "${GREEN}==============================================${NC}"

cd cloud/deploy/aws/terraform
WEBSITE_URL=$(terraform output -raw website_url 2>/dev/null)
echo -e ""
echo -e "${YELLOW}👉 URL SITO WEB:${NC} ${GREEN}$WEBSITE_URL${NC}"
echo -e "${YELLOW}(Attendi ~3 minuti che la GitHub Action finisca il deploy su Kubernetes prima di collegarti!)${NC}"
echo -e ""
