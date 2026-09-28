# Cloud-Native AI: Graph-based Semantic Image Retrieval

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Descrizione del Progetto

Questo progetto unisce **Deep Learning** e **Cloud Computing** per creare un sistema di ricerca semantica di immagini basato su grafi, containerizzato a microservizi e orchestrato su Kubernetes, sia in ambiente locale che su AWS.

### Pipeline AI (Deep Learning)
Il core del progetto è un modello di Graph Neural Network (GCN) addestrato in modo contrastivo per la ricerca per similarità. Ogni immagine del dataset GQA viene rappresentata come **Scene Graph**, arricchito tramite inferenza ontologica (Virtuoso + NOMIC) e compresso in un embedding vettoriale a 256 dimensioni da un graph encoder (GINEConv/SAGEConv). Gli embedding vengono indicizzati con **FAISS** e interrogati per similarità, con encoder visivi congelati (ResNet50, CLIP) come baseline di confronto.

L'utente può:
1. **Selezionare un'immagine di test** dalla galleria (embedding pre-calcolati → ricerca veloce).
2. **Caricare una nuova foto**: viene processata da un **Vision-Language Model (Qwen 2.5 7b)** sul cluster HPC universitario per estrarne il scene graph, poi il grafo viene vettorizzato dalla GCN e cercato in FAISS.

### Architettura Cloud-Native (Sistemi Cloud)
La pipeline AI, originariamente monolitica e sincrona, è stata scomposta in **microservizi containerizzati** (Docker) e orchestrata con **Kubernetes (K3s)**, prima su un cluster locale (Multipass) e poi migrata su **AWS** tramite Terraform (Infrastructure as Code).

**Architettura a microservizi:**
- **Frontend** (React/Vite) — Interfaccia utente con polling asincrono.
- **Backend** (FastAPI) — API Gateway che registra i job e gestisce il polling.
- **NGINX** (Ingress) — Reverse proxy Layer 7 che smista il traffico.
- **Worker AI** (PyTorch) — Elaborazione AI pesante, scalato da KEDA.
- **Message Broker** — RabbitMQ (locale) / Amazon SQS (cloud).
- **Database** — PostgreSQL (locale) / Amazon RDS (cloud).
- **Cache & Lock** — Redis (locale) / Amazon ElastiCache (cloud).

**Servizi AWS:**
- **S3** — Storage delle immagini e dei modelli AI.
- **Lambda** — Trigger serverless su upload S3 → accodamento SQS.
- **KEDA** — Autoscaling event-driven basato sulla lunghezza della coda SQS.
- **Distributed Lock (Redis)** — Semaforo per serializzare l'accesso alla GPU dell'HPC.

> **Relazione completa**: per i dettagli teorici sull'AI si rimanda a **[REPORT.md](docs/REPORT.md)**.

---

## Quick Start

### Prerequisiti
- Docker & Docker Compose
- AWS CLI configurato (per il deploy cloud)
- Terraform ≥ 1.5
- Ansible ≥ 2.14
- Node.js ≥ 18 (per lo sviluppo frontend)
- Conda/Mamba (per l'ambiente Python AI)

### 1. Configurazione
```bash
git clone https://github.com/flynow-unict/scene-graph-metric-learning.git
cd scene-graph-metric-learning
cp project_config.env.template project_config.env
# Compila project_config.env con le tue credenziali AWS, HPC e i path locali
```

### 2. Deploy Locale (Multipass + K3s)
```bash
# Crea 3 VM locali (1 Master, 2 Worker) con K3s
cd cloud/deploy/local
./setup_multipass.sh

# Installa K3s con Ansible
cd ../../ansible
ansible-playbook -i inventory/hosts.ini site.yml

# Aggiorna gli IP dinamici e carica le immagini Docker
cd ../deploy/local
./update_cluster_ip.sh
export KUBECONFIG=$(pwd)/kubeconfig
./load_images_k3s.sh
kubectl apply -f k8s/

# Inizializza il database
kubectl exec deployment/backend -- python -c "from main import init_db; init_db()"
```

### 3. Deploy Cloud (AWS)
Un singolo script automatizza l'intero processo: provisioning Terraform, configurazione Ansible, upload dati su S3, push segreti su GitHub e trigger della CI/CD pipeline.
```bash
./deploy_cloud.sh
```

Lo script esegue in sequenza:
1. `terraform init` + `terraform apply` — Crea VPC, Subnet, EC2, RDS, ElastiCache, ALB, S3, SQS, Lambda.
2. Genera l'inventario Ansible con gli IP delle EC2.
3. Carica i segreti (chiavi SSH, credenziali HPC e AWS) su GitHub Secrets.
4. Sincronizza i dati pesanti (modelli, immagini, FAISS) su S3.
5. Triggera la GitHub Action `master-pipeline.yml` per il deploy su Kubernetes.

### 4. Distruzione Infrastruttura
```bash
cd cloud/deploy/aws/terraform
terraform destroy --auto-approve
```

---

## Addestramento AI

### Ambiente Python
```bash
conda env create -f environment.yml
conda activate dl-scene-retrieval
```

### Training
```bash
# Modello principale — GINE + Triplet Loss
python -m src.training.train --config experiments/configs/gine_triplet.yaml

# Baseline — solo topologia del grafo
python -m src.training.train --config experiments/configs/baseline.yaml
```

### Valutazione
```bash
python -m src.evaluation.build_relevance --config experiments/configs/relevance.yaml
python -m src.evaluation.extract_gcn_embeddings --config experiments/configs/extract_gine_triplet.yaml
python -m src.evaluation.build_faiss_index && python -m src.evaluation.evaluate
```

---

## Risultati AI

Confronto sul corpus ridotto (15k scene, 771 query), retrieval a K=10:

| Modello | Precision@10 | Recall@10 | HitRate@10 |
|---|---:|---:|---:|
| GCN semantica, GINE + Triplet | 15.71 | 39.85 | 74.45 |
| GCN semantica, SAGE + Triplet | 15.16 | 38.29 | 71.98 |
| GCN semantica, GINE + NT-Xent | 14.51 | 36.38 | 70.04 |
| CLIP ViT-B/32 (solo pixel) | 6.86 | 17.59 | 37.35 |
| ResNet50 (solo pixel) | 6.38 | 16.26 | 36.96 |

---

## Struttura della Repository

```
├── cloud/                      # Infrastruttura Cloud e Microservizi
│   ├── backend/                #   FastAPI (API Gateway + Business Logic)
│   ├── frontend/               #   React/Vite (UI + Polling asincrono)
│   ├── workerAI/               #   Worker AI (PyTorch, GCN, VLM)
│   ├── lambda/                 #   AWS Lambda (trigger S3 → SQS)
│   ├── db_schema/              #   Schema PostgreSQL
│   ├── ansible/                #   Playbook Ansible (setup K3s/K8s)
│   └── deploy/                 #   Manifesti K8s e Terraform
│       ├── local/              #     Multipass + K3s locale
│       └── aws/                #     AWS (Terraform + Ansible + K8s)
│           ├── terraform/      #       VPC, EC2, RDS, ElastiCache, ALB, S3, SQS, Lambda
│           ├── ansible/        #       Installazione K3s/K8s sui nodi EC2
│           └── k8s/            #       Manifesti Kubernetes per il cloud
│
├── src/                        # Pipeline AI (Deep Learning)
│   ├── datasets/               #   Costruzione scene graph, split, embedding
│   ├── models/                 #   Graph encoder (GINEConv, SAGEConv) e baseline
│   ├── training/               #   Loop contrastivo e funzioni di loss
│   ├── evaluation/             #   FAISS, metriche, robustezza, explainability
│   ├── semantic_web/           #   Client SPARQL, ontologia, Virtuoso
│   └── utils/                  #   Configurazioni e utility
│
├── data/                       # Dataset, embedding e checkpoint (non versionati)
├── experiments/                # Configs YAML, job SLURM, logs di training
├── figures/                    # Grafici di valutazione
├── docs/                       # Relazione AI e risultati dettagliati
├── deploy_cloud.sh             # Script principale di deploy automatizzato
├── project_config.env          # Variabili d'ambiente (non versionato)
└── environment.yml             # Dipendenze Conda/Python
```

---

## Tecnologie Utilizzate

| Categoria | Strumento |
|---|---|
| **AI / ML** | PyTorch, PyG (torch_geometric), FAISS, NOMIC, Qwen 2.5 VLM |
| **Frontend** | React, Vite |
| **Backend** | FastAPI, Python |
| **Containerizzazione** | Docker, containerd |
| **Orchestrazione** | Kubernetes (K3s / Kubeadm), NGINX Ingress |
| **IaC** | Terraform (HCL), Ansible |
| **Cloud (AWS)** | EC2, VPC, RDS, ElastiCache, S3, SQS, Lambda, ALB |
| **Autoscaling** | KEDA (Event-Driven), Distributed Lock (Redis) |
| **CI/CD** | GitHub Actions |
| **Monitoring** | kubectl, AWS CloudWatch |

---

## Gruppo
- **Group ID**: FlyNow
- **Project ID**: 26

*Per la dichiarazione dei task individuali e dell'uso dell'AI si rimanda a [`docs/REPORT.md`](docs/REPORT.md).*
