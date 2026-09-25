#!/bin/bash
set -e

# Relative path to avoid hardcoded absolute paths in the repository
DATA_DIR="../Deep Learning/Progetto/data"
BUCKET="s3://sistemi-cloud-data-santi"

echo "=========================================================="
echo "[*] Starting upload of LIGHT dataset version to bucket $BUCKET"
echo "=========================================================="

# 1. Images
echo "[*] Uploading images (Test and VectorDB)..."
aws s3 sync "$DATA_DIR/images/fullset/Test" "$BUCKET/images/fullset/Test"
aws s3 sync "$DATA_DIR/images/fullset/VectorDB" "$BUCKET/images/fullset/VectorDB"

# 2. Scene Graph
echo "[*] Uploading Scene Graph (embedded semantic and json)..."
aws s3 sync "$DATA_DIR/sceneGraph/fullset/semantic/embedded" "$BUCKET/sceneGraph/fullset/semantic/embedded"
aws s3 sync "$DATA_DIR/sceneGraph/json" "$BUCKET/sceneGraph/json"

# 3. Models & Checkpoints
echo "[*] Uploading Models and Checkpoints..."
aws s3 sync "$DATA_DIR/models/fullset/checkpoints" "$BUCKET/models/fullset/checkpoints"

echo "[*] Uploading Semantic Embeddings (ignoring cross and reverse)..."
aws s3 sync "$DATA_DIR/models/fullset/semantic_web/gcn" "$BUCKET/models/fullset/semantic_web/gcn" \
    --exclude "*cross*" \
    --exclude "*reverse*"

echo "[*] Uploading Visual Baselines (ResNet and CLIP)..."
aws s3 sync "$DATA_DIR/models/fullset/baseline/vision" "$BUCKET/models/fullset/baseline/vision"

echo "[*] Uploading FAISS..."
aws s3 sync "$DATA_DIR/models/fullset/faiss" "$BUCKET/models/fullset/faiss" \
    --exclude "baseline_gcn*" \
    --exclude "*cross*" \
    --exclude "*reverse*"

echo "=========================================================="
echo "[OK] Upload completed successfully!"
echo "=========================================================="
