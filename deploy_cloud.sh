#!/bin/bash
set -e

# Colori per logging
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}   CLOUD SYSTEMS AUTOMATED DEPLOYMENT       ${NC}"
echo -e "${GREEN}==============================================${NC}"

if [ ! -f "project_config.env" ]; then
    echo -e "${RED}[ERROR] File project_config.env not found! Copy the template and fill it out.${NC}"
    exit 1
fi

source project_config.env

echo -e "${YELLOW}[+] 1. AWS Infrastructure Provisioning (Terraform)...${NC}"
cd cloud/deploy/aws/terraform
terraform apply -auto-approve

echo -e "${YELLOW}[+] 2. Extracting IP for Ansible...${NC}"
MASTER_IP=$(terraform output -raw master_ip)
MASTER_PRIV_IP=$(terraform output -raw master_private_ip)
WORKER1_IP=$(terraform output -raw worker_1_ip)
WORKER2_IP=$(terraform output -raw worker_2_ip)

cd ../ansible
echo -e "${YELLOW}[+] 3. Automatically updating inventory/hosts.ini file...${NC}"
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

echo -e "${YELLOW}[+] 4. Loading Secrets to GitHub (HPC and AWS)...${NC}"
# Setup SSH key created by terraform
gh secret set EC2_SSH_KEY < cloud/deploy/aws/terraform/k8s_key.pem --repo $GITHUB_REPO_NAME
gh secret set EC2_HOST --body "$MASTER_IP" --repo $GITHUB_REPO_NAME

# Setup HPC credentials
gh secret set HPC_CLUSTER_USER --body "$CLUSTER_USER" --repo $GITHUB_REPO_NAME
gh secret set HPC_CLUSTER_HOST --body "$CLUSTER_HOST" --repo $GITHUB_REPO_NAME
gh secret set HPC_CLUSTER_PW --body "$CLUSTER_PW" --repo $GITHUB_REPO_NAME

# Fetch AWS keys if not set in environment
if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)
fi
if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key)
fi

# Setup AWS credentials for Backend
gh secret set AWS_ACCESS_KEY_ID --body "$AWS_ACCESS_KEY_ID" --repo $GITHUB_REPO_NAME
gh secret set AWS_SECRET_ACCESS_KEY --body "$AWS_SECRET_ACCESS_KEY" --repo $GITHUB_REPO_NAME


echo -e "${YELLOW}[+] 5. Syncing Heavy Data (.pt, FAISS, Images) to S3 from local...${NC}"
if [ -n "$LOCAL_DATA_DIR" ]; then
    echo "Syncing FAISS (Indices)..."
    aws s3 sync "$LOCAL_DATA_DIR/models/fullset/faiss" "s3://$AWS_S3_BUCKET_NAME/models/fullset/faiss" --exclude "*.gitkeep"
    
    echo "Syncing Checkpoints (Trained models)..."
    aws s3 sync "$LOCAL_DATA_DIR/models/fullset/checkpoints" "s3://$AWS_S3_BUCKET_NAME/models/fullset/checkpoints" --exclude "*.gitkeep"
    
    echo "Syncing Baseline Models and Tensors (.pt)..."
    aws s3 sync "$LOCAL_DATA_DIR/models/fullset/baseline" "s3://$AWS_S3_BUCKET_NAME/models/fullset/baseline" --exclude "*.gitkeep"
    
    echo "Syncing Semantic Web Models (GCN and Tensors)..."
    aws s3 sync "$LOCAL_DATA_DIR/models/fullset/semantic_web" "s3://$AWS_S3_BUCKET_NAME/models/fullset/semantic_web" --exclude "*.gitkeep"
    
    echo "Syncing Test Images (imagesTest)..."
    aws s3 sync "$LOCAL_DATA_DIR/images/fullset/Test" "s3://$AWS_S3_BUCKET_NAME/images/fullset/Test" --exclude "*.gitkeep"
    
    echo "Syncing Images for VectorDB (VectorDB)..."
    aws s3 sync "$LOCAL_DATA_DIR/images/fullset/VectorDB" "s3://$AWS_S3_BUCKET_NAME/images/fullset/VectorDB" --exclude "*.gitkeep"
    
    echo "Syncing Test Queries Scene Graphs (.pt)..."
    aws s3 cp "$LOCAL_DATA_DIR/sceneGraph/fullset/semantic/embedded/test_queries_scene_graphs.pt" "s3://$AWS_S3_BUCKET_NAME/sceneGraph/fullset/semantic/embedded/test_queries_scene_graphs.pt"
    
    echo "Syncing Test Gallery Scene Graphs (.pt) [Embeddings]..."
    
    echo "Syncing JSON (Graphs for Frontend)..."
    aws s3 sync "$LOCAL_DATA_DIR/sceneGraph/json" "s3://$AWS_S3_BUCKET_NAME/sceneGraph/json" --exclude "*.gitkeep"

    echo "Syncing Scene Graphs Raw (.pt)..."
    aws s3 cp "$LOCAL_DATA_DIR/sceneGraph/fullset/semantic/raw/test_queries_scene_graphs.pt" "s3://$AWS_S3_BUCKET_NAME/sceneGraph/fullset/semantic/raw/test_queries_scene_graphs.pt"
    aws s3 cp "$LOCAL_DATA_DIR/sceneGraph/fullset/semantic/raw/test_gallery_scene_graphs.pt" "s3://$AWS_S3_BUCKET_NAME/sceneGraph/fullset/semantic/raw/test_gallery_scene_graphs.pt"
else
    echo -e "${RED}[WARNING] LOCAL_DATA_DIR not set, skipping S3 sync.${NC}"
fi

echo -e "${YELLOW}[+] 6. Pushing infrastructure changes to Git...${NC}"
git add cloud/deploy/aws/ansible/inventory/hosts.ini
if ! git diff-index --quiet HEAD; then
    git commit -m "chore(infra): auto-update Ansible hosts.ini via deploy script"
    git push origin main
else
    echo "No changes to hosts.ini to push."
fi

echo -e "${YELLOW}[+] 7. Triggering Master Pipeline GitHub Action...${NC}"
gh workflow run master-pipeline.yml --repo $GITHUB_REPO_NAME

echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}   EVERYTHING STARTED SUCCESSFULLY!           ${NC}"
echo -e "${GREEN}   Check the GitHub repository to see         ${NC}"
echo -e "${GREEN}   the deployment status!                     ${NC}"
echo -e "${GREEN}==============================================${NC}"

cd cloud/deploy/aws/terraform
WEBSITE_URL=$(terraform output -raw website_url 2>/dev/null)
echo -e ""
echo -e "${YELLOW}[>] WEBSITE URL:${NC} ${GREEN}$WEBSITE_URL${NC}"
echo -e "${YELLOW}(Wait ~3 minutes for the GitHub Action to finish the deployment on Kubernetes before connecting!)${NC}"
echo -e ""
