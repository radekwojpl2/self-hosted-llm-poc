#!/usr/bin/env bash
# $1 = model to pull (e.g. qwen2.5:14b, deepseek-r1:14b)
# $2 = context size override (optional, e.g. 32768); uses per-model default if omitted
set -euxo pipefail

MODEL="${1:?model name required}"
ollama pull "$MODEL"

# Resolve default context size and variant name per model.
case "$MODEL" in
  qwen2.5:14b)    DEFAULT_CTX=20480;  VARIANT="qwen2.5-14b"    ;;
  qwen2.5:32b)    DEFAULT_CTX=131072; VARIANT="qwen2.5-32b"    ;;
  qwen2.5:72b)    DEFAULT_CTX=32768;  VARIANT="qwen2.5-72b"    ;;
  deepseek-r1:14b) DEFAULT_CTX=32768; VARIANT="deepseek-r1"    ;;
  *) DEFAULT_CTX=0; VARIANT="" ;;
esac

CTX="${2:-$DEFAULT_CTX}"

if [ -n "$VARIANT" ] && [ "$CTX" -gt 0 ]; then
  # Convert ctx to a human-readable suffix: 131072 -> 128k, 32768 -> 32k, 20480 -> 20k
  SUFFIX="${CTX}"
  case "$CTX" in
    131072) SUFFIX="128k" ;;
    65536)  SUFFIX="64k"  ;;
    32768)  SUFFIX="32k"  ;;
    20480)  SUFFIX="20k"  ;;
    16384)  SUFFIX="16k"  ;;
    8192)   SUFFIX="8k"   ;;
    *)      SUFFIX="${CTX}" ;;
  esac
  NAME="${VARIANT}-${SUFFIX}"
  MODELFILE=$(mktemp)
  printf 'FROM %s\nPARAMETER num_ctx %s\n' "$MODEL" "$CTX" > "$MODELFILE"
  ollama create "$NAME" -f "$MODELFILE"
  rm "$MODELFILE"
fi

echo "=== Installed models ==="
ollama list
