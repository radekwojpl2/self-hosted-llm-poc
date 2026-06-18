#!/usr/bin/env bash
set -euxo pipefail
export HOME=/root

FILENAME="$1"
TEMPLATE="$2"
MODEL="$3"
LANG="${4:-en}"

FILE_PATH="/mnt/models/hyper-extract-input/${FILENAME}"
RUN_ID="$(date +%Y%m%d-%H%M%S)-$(basename "$FILENAME" | sed 's/\.[^.]*$//')"
OUTPUT_DIR="/mnt/models/hyper-extract-output/${RUN_ID}"
mkdir -p "$OUTPUT_DIR"

he config llm \
  --provider vllm \
  --model "$MODEL" \
  --api-key ollama \
  --base-url http://localhost:11434/v1

he config embedder \
  --provider vllm \
  --model nomic-embed-text \
  --api-key ollama \
  --base-url http://localhost:11434/v1

he parse "$FILE_PATH" -t "$TEMPLATE" -o "$OUTPUT_DIR" --lang "$LANG"
