#!/usr/bin/env bash
# $1 = model to pull (e.g. qwen2.5:14b, deepseek-r1:14b)
set -euxo pipefail

MODEL="${1:?model name required}"
ollama pull "$MODEL"

# Create context-extended variants for known models.
case "$MODEL" in
  qwen2.5:14b)
    MODELFILE=$(mktemp)
    printf 'FROM qwen2.5:14b\nPARAMETER num_ctx 20480\n' > "$MODELFILE"
    ollama create qwen2.5-14b-20k -f "$MODELFILE"
    rm "$MODELFILE"
    ;;
  qwen2.5:32b)
    MODELFILE=$(mktemp)
    printf 'FROM qwen2.5:32b\nPARAMETER num_ctx 131072\n' > "$MODELFILE"
    ollama create qwen2.5-32b-128k -f "$MODELFILE"
    rm "$MODELFILE"
    ;;
  qwen2.5:72b)
    MODELFILE=$(mktemp)
    printf 'FROM qwen2.5:72b\nPARAMETER num_ctx 32768\n' > "$MODELFILE"
    ollama create qwen2.5-72b-32k -f "$MODELFILE"
    rm "$MODELFILE"
    ;;
  deepseek-r1:14b)
    MODELFILE=$(mktemp)
    printf 'FROM deepseek-r1:14b\nPARAMETER num_ctx 32768\n' > "$MODELFILE"
    ollama create deepseek-r1-32k -f "$MODELFILE"
    rm "$MODELFILE"
    ;;
esac

echo "=== Installed models ==="
ollama list
