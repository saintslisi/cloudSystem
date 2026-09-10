import os
import subprocess
import time
import re
from dotenv import load_dotenv

load_dotenv()
# =====================================================================
# CONFIGURAZIONE CLUSTER SLURM (Modifica con i tuoi parametri)
# =====================================================================
CLUSTER_USER = os.getenv("CLUSTER_USER") # Il tuo username sul cluster
CLUSTER_HOST = os.getenv("CLUSTER_HOST") # Sostituisci con l'hostname o l'IP del server di login (es. hpc.unipa.it)
CLUSTER_PROJECT_DIR = f"/home/{CLUSTER_USER}/Progetto" # Path assoluto della root del Progetto di Deep Learning
SSH_TARGET = f"{CLUSTER_USER}@{CLUSTER_HOST}"
print(SSH_TARGET)
# Nomi degli script sbatch sul cluster (adattali se hanno nomi diversi)
SBATCH_VLM_SCRIPT = "script/VLM/run_vlm_cluster.sh"
SBATCH_OLLAMA_SCRIPT = "script/DataLoader/run_embeddings_cluster.sh"
# =====================================================================


import paramiko
from scp import SCPClient

CLUSTER_PW = os.getenv("CLUSTER_PW")

def get_ssh_client():
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(hostname=CLUSTER_HOST, username=CLUSTER_USER, password=CLUSTER_PW)
    return ssh

def run_ssh_command(command):
    """Esegue un comando remoto via SSH e ritorna l'output"""
    print(f"[SSH] Eseguo: {command}")
    with get_ssh_client() as ssh:
        stdin, stdout, stderr = ssh.exec_command(command)
        exit_status = stdout.channel.recv_exit_status()
        out = stdout.read().decode().strip()
        err = stderr.read().decode().strip()
        if exit_status != 0:
            raise Exception(f"Errore SSH [{command}]:\n{err}")
        return out

def upload_file(local_path, remote_path):
    """Carica un file sul cluster via SCP"""
    logging.info(f"[SCP Upload] {local_path} -> {SSH_TARGET}:{remote_path}")
    with get_ssh_client() as ssh:
        with SCPClient(ssh.get_transport()) as scp:
            scp.put(local_path, remote_path)

def download_file(remote_path, local_path):
    """Scarica un file dal cluster via SCP"""
    logging.info(f"[SCP Download] {SSH_TARGET}:{remote_path} -> {local_path}")
    with get_ssh_client() as ssh:
        with SCPClient(ssh.get_transport()) as scp:
            scp.get(remote_path, local_path)


def wait_for_job(job_id):
    """Esegue il polling di squeue finché il job non sparisce dalla coda"""
    logging.info(f"[SLURM] Attesa completamento Job {job_id}...")
    while True:
        stdout = run_ssh_command(f"squeue -j {job_id} -h")
        if not stdout.strip():
            logging.info(f"[SLURM] Job {job_id} completato e rimosso dalla coda.")
            break
        time.sleep(10)  # Controlla ogni 10 secondi per non inondare il server di richieste


def submit_sbatch(script_path, args=""):
    """Sottomette un job sbatch sul cluster e ne estrae il Job ID"""
    command = f"cd {CLUSTER_PROJECT_DIR} && sbatch {script_path} {args}"
    stdout = run_ssh_command(command)
    # Output tipico di sbatch: "Submitted batch job 12345"
    match = re.search(r"Submitted batch job (\d+)", stdout)
    if match:
        job_id = match.group(1)
        print(f"[SLURM] Sottomesso sbatch '{script_path}' con ID: {job_id}")
        return job_id
    else:
        raise Exception(f"Impossibile leggere l'ID del job dall'output: {stdout}")


def run_vlm_phase(job_id_db: str, image_filename: str):
    """
    Gestisce il caricamento dell'immagine e l'estrazione dello Scene Graph tramite VLM.
    """
    logging.info("\n" + "="*50)
    logging.info(f"AVVIO FASE VLM PER JOB: {job_id_db}")
    logging.info("="*50)
    
    candidates = [
        os.path.join("/tmp", image_filename),
        os.path.join("data", "images", "inference", image_filename),
        os.path.join("/app", "data", "images", "inference", image_filename),
        os.path.abspath(os.path.join("data", "images", "inference", image_filename))
    ]
    local_image_path = next((p for p in candidates if os.path.exists(p)), candidates[0])
    remote_image_path = f"{CLUSTER_PROJECT_DIR}/data/images/inference/{image_filename}"
    
    if not os.path.exists(local_image_path):
        raise FileNotFoundError(f"Immagine non trovata in locale per upload HPC: {local_image_path}")

    # Fase 1: Creazione cartelle remote e Upload Immagine
    logging.info("\n--- FASE 1: Upload Immagine e Sincronizzazione Script ---")
    run_ssh_command(f"mkdir -p {CLUSTER_PROJECT_DIR}/data/images/inference {CLUSTER_PROJECT_DIR}/data/sceneGraph/Raw/inference {CLUSTER_PROJECT_DIR}/data/sceneGraph/embedded/inference {CLUSTER_PROJECT_DIR}/logs")
    upload_file(local_image_path, remote_image_path)
    
    # Sincronizza lo script VLM per avere sempre le ultime mapping delle categorie!
    extractor_candidates = [
        "/app/src/datasets/vlm_extractor.py",
        os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "src", "datasets", "vlm_extractor.py"),
        os.path.join(os.path.dirname(__file__), "vlm_extractor.py")
    ]
    local_script = next((p for p in extractor_candidates if os.path.exists(p)), None)
    if local_script:
        upload_file(local_script, f"{CLUSTER_PROJECT_DIR}/script/VLM/dynamic_extractor.py")
    
    # Fase 2: Lancio Estrazione Grafo (Qwen2.5-VL)
    logging.info("\n--- FASE 2: Estrazione VLM ---")
    vlm_job_id = submit_sbatch(SBATCH_VLM_SCRIPT, args=f"Qwen/Qwen2.5-VL-7B-Instruct data/images/inference/{image_filename} {job_id_db}")
    wait_for_job(vlm_job_id)

    logging.info("\n--- Download Risultato VLM ---")
    remote_raw_pt = f"{CLUSTER_PROJECT_DIR}/data/sceneGraph/Raw/inference/{job_id_db}.pt"
    local_raw_dir = os.path.join("data", "sceneGraph", "Raw", "inference")
    try:
        os.makedirs(local_raw_dir, exist_ok=True)
    except:
        pass
    local_raw_pt = os.path.join(local_raw_dir, f"{job_id_db}.pt")
    
    tmp_raw_pt = f"/tmp/raw_{job_id_db}.pt"
    download_file(remote_raw_pt, tmp_raw_pt)
    os.system(f"cp {tmp_raw_pt} {local_raw_pt}")
    
    logging.info(f"VLM Completato. File Raw scaricato in: {local_raw_pt}")
    return local_raw_pt

def run_embedding_phase(job_id_db: str, image_filename: str = None):
    """
    Gestisce la generazione degli embedding tramite Nomic e scarica il risultato finale.
    """
    print("\n" + "="*50)
    print(f"AVVIO FASE EMBEDDING PER JOB: {job_id_db}")
    print("="*50)

    # Fase 3: Lancio Generazione Embedding
    print("\n--- FASE 3: Generazione Embedding ---")
    emb_job_id = submit_sbatch(SBATCH_OLLAMA_SCRIPT, args=f"{job_id_db}")
    wait_for_job(emb_job_id)
    
    # Fase 4: Download Risultati
    print("\n--- FASE 4: Download Risultato Embedding ---")
    remote_emb_pt = f"{CLUSTER_PROJECT_DIR}/data/sceneGraph/embedded/inference/{job_id_db}.pt"
    local_emb_dir = os.path.join("data", "sceneGraph", "embedded", "inference")
    try:
        os.makedirs(local_emb_dir, exist_ok=True)
    except:
        pass
    local_emb_pt = os.path.join(local_emb_dir, f"{job_id_db}.pt")
    
    tmp_emb_pt = f"/tmp/emb_{job_id_db}.pt"
    download_file(remote_emb_pt, tmp_emb_pt)
    os.system(f"cp {tmp_emb_pt} {local_emb_pt}")
    
    # Opzionale: Pulizia immagine remota se è stato fornito il filename
    if image_filename:
        remote_image_path = f"{CLUSTER_PROJECT_DIR}/data/images/inference/{image_filename}"
        run_ssh_command(f"rm {remote_image_path}")
        
    return tmp_emb_pt
    
    print("\n" + "="*50)
    print(f"INFERENZA COMPLETATA. File Embedded scaricato in:")
    print(f"- {local_emb_pt}")
    print("="*50)
    
    return local_emb_pt

if __name__ == "__main__":
    # Test isolato dell'orchestratore
    #job_id = "101"
    #filename = "101.jpg"
    #run_vlm_phase(job_id, filename)
    #run_embedding_phase(job_id, filename)
    pass
