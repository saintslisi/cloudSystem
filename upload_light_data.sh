#!/bin/bash
set -e

DATA_DIR="/media/santi/Shared3/utenti/santi/universita/Magistrale/I anno/II Semestre/Deep Learning/Progetto/data"
BUCKET="s3://sistemi-cloud-data-santi"

echo "=========================================================="
echo "Inizio upload versione LIGHT del dataset sul bucket $BUCKET"
echo "=========================================================="

# 1. Immagini
echo "Caricamento immagini (Test e VectorDB)..."
aws s3 sync "$DATA_DIR/images/fullset/Test" "$BUCKET/images/fullset/Test"
aws s3 sync "$DATA_DIR/images/fullset/VectorDB" "$BUCKET/images/fullset/VectorDB"

# 2. Scene Graph
echo "Caricamento Scene Graph (embedded semantic e json)..."
aws s3 sync "$DATA_DIR/sceneGraph/fullset/semantic/embedded" "$BUCKET/sceneGraph/fullset/semantic/embedded"
aws s3 sync "$DATA_DIR/sceneGraph/json" "$BUCKET/sceneGraph/json"

# 3. Modelli & Checkpoint
echo "Caricamento Modelli e Checkpoint..."
aws s3 sync "$DATA_DIR/models/fullset/checkpoints" "$BUCKET/models/fullset/checkpoints"

echo "Caricamento Embedding Semantici (ignorando cross e reverse)..."
aws s3 sync "$DATA_DIR/models/fullset/semantic_web/gcn" "$BUCKET/models/fullset/semantic_web/gcn" \
    --exclude "*cross*" \
    --exclude "*reverse*"

echo "Caricamento Baseline Visive (ResNet e CLIP)..."
aws s3 sync "$DATA_DIR/models/fullset/baseline/vision" "$BUCKET/models/fullset/baseline/vision"

echo "Caricamento FAISS..."
aws s3 sync "$DATA_DIR/models/fullset/faiss" "$BUCKET/models/fullset/faiss" \
    --exclude "baseline_gcn*" \
    --exclude "*cross*" \
    --exclude "*reverse*"

echo "=========================================================="
echo "✅ Upload completato con successo!"
echo "=========================================================="
