#!/bin/bash

# Resource Configuration
MASTER_CPU=2
MASTER_RAM="2G"
MASTER_DISK="10G"

WORKER1_CPU=2
WORKER1_RAM="2G"
WORKER1_DISK="15G"

WORKER2_CPU=4
WORKER2_RAM="4G"
WORKER2_DISK="20G" # Larger to download containers and data

# Real path of local data folder
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"

# Load global configuration file if it exists
if [ -f "$PROJECT_ROOT/project_config.env" ]; then
    set -a
    source "$PROJECT_ROOT/project_config.env"
    set +a
    DATA_PATH="$LOCAL_DATA_DIR"
fi

if [ -z "$DATA_PATH" ]; then
    if [ -n "$1" ]; then
        DATA_PATH="$1"
    else
        echo "[ERROR] Data path not specified."
        echo "You must fill LOCAL_DATA_DIR in the project_config.env file in the project root."
        echo "Or pass it as an argument: ./setup_multipass.sh /your/path"
        exit 1
    fi
fi

# Convert to absolute path to avoid Multipass mount issues
DATA_PATH=$(realpath "$DATA_PATH")

set -e # Stop script on first error

echo "============================================="
echo "[+] Starting K3s Cluster Creation with Multipass"
echo "============================================="

# Check if multipass is installed
if command -v multipass &> /dev/null; then
    MULTIPASS_CMD="multipass"
elif [ -x "/snap/bin/multipass" ]; then
    MULTIPASS_CMD="/snap/bin/multipass"
else
    echo "[ERROR] Multipass is not installed. Run 'sudo snap install multipass' before continuing."
    exit 1
fi

echo "[*] Cleaning up any deleted virtual machines (purge)..."
$MULTIPASS_CMD purge 2>/dev/null || true

echo "[*] Updating Multipass image list..."
$MULTIPASS_CMD find > /dev/null

echo "[1] Creating k3s-master..."
$MULTIPASS_CMD launch 22.04 --name k3s-master --cpus $MASTER_CPU --memory $MASTER_RAM --disk $MASTER_DISK --timeout 600
echo "[OK] k3s-master created!"

echo "[2] Creating k3s-worker-1 (Frontend/Backend)..."
$MULTIPASS_CMD launch 22.04 --name k3s-worker-1 --cpus $WORKER1_CPU --memory $WORKER1_RAM --disk $WORKER1_DISK --timeout 600
echo "[OK] k3s-worker-1 created!"

echo "[3] Creating k3s-worker-2 (AI Worker)..."
$MULTIPASS_CMD launch 22.04 --name k3s-worker-2 --cpus $WORKER2_CPU --memory $WORKER2_RAM --disk $WORKER2_DISK --timeout 600
echo "[OK] k3s-worker-2 created!"

echo "[*] Temporary DNS fix on virtual machines to prevent download issues..."
for node in k3s-master k3s-worker-1 k3s-worker-2; do
    $MULTIPASS_CMD exec $node -- sudo bash -c "unlink /etc/resolv.conf && echo 'nameserver 8.8.8.8' > /etc/resolv.conf"
done
echo "[OK] DNS set to 8.8.8.8 on all VMs!"

echo "[*] Mounting data folder in k3s-worker-1 and k3s-worker-2..."
# Create the folder beforehand in the VMs and set permissions to avoid PermissionError (UID 1000)
$MULTIPASS_CMD exec k3s-worker-1 -- sudo bash -c "mkdir -p /app/data && chmod 777 /app/data"
$MULTIPASS_CMD exec k3s-worker-2 -- sudo bash -c "mkdir -p /app/data && chmod 777 /app/data"

if [ -d "$DATA_PATH" ]; then
    # The mount uses the multipass-sshfs plugin downloaded from the Snap Store.
    # If the Canonical CDN is temporarily unreachable (error 502/503),
    # the mount fails but the K3s cluster will still work. We proceed without blocking.
    if $MULTIPASS_CMD mount "$DATA_PATH" k3s-worker-1:/app/data 2>&1 && \
       $MULTIPASS_CMD mount "$DATA_PATH" k3s-worker-2:/app/data 2>&1; then
        echo "[OK] Folder successfully mounted in both workers!"
    else
        echo "[WARN] Mount failed (likely Snap CDN outage). The cluster will continue to work."
        echo "    To mount manually later, run:"
        echo "    multipass mount $(realpath $DATA_PATH) k3s-worker-1:/app/data"
        echo "    multipass mount $(realpath $DATA_PATH) k3s-worker-2:/app/data"
    fi
else
    echo "[WARN] ATTENTION: The folder $DATA_PATH does not exist. Create and mount it manually."
fi

echo "============================================="
echo "[*] Retrieving IP Addresses and Ansible Setup"
echo "============================================="

MASTER_IP=$($MULTIPASS_CMD info k3s-master | grep IPv4 | awk '{print $2}')
WORKER1_IP=$($MULTIPASS_CMD info k3s-worker-1 | grep IPv4 | awk '{print $2}')
WORKER2_IP=$($MULTIPASS_CMD info k3s-worker-2 | grep IPv4 | awk '{print $2}')

echo "k3s-master: $MASTER_IP"
echo "k3s-worker-1: $WORKER1_IP"
echo "k3s-worker-2: $WORKER2_IP"

CLOUD_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
# Creating the Ansible inventory
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

echo "[OK] Ansible inventory generated in ansible/inventory/hosts.ini!"

echo "[*] Injecting user SSH key (~/.ssh/id_rsa.pub) into VMs for Ansible..."
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

echo "[OK] ansible.cfg file created and SSH keys configured successfully!"
echo "[OK] VM setup completed! You can now run the Ansible playbooks."
