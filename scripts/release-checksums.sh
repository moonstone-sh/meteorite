#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
  echo "Usage: $0 <artifact-directory> [output-file]" >&2
  exit 2
fi

ARTIFACT_ROOT="$1"
OUTPUT_FILE="${2:-}"

if [[ ! -d "$ARTIFACT_ROOT" ]]; then
  echo "release checksums: directory not found: $ARTIFACT_ROOT" >&2
  exit 1
fi

checksum() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path"
  else
    shasum -a 256 "$path"
  fi
}

if [[ -n "$OUTPUT_FILE" ]]; then
  exec > "$OUTPUT_FILE"
fi

(
  cd "$ARTIFACT_ROOT"
  while IFS= read -r -d '' artifact; do
    checksum "${artifact#./}"
  done < <(find . -type f -print0 | sort -z)
)
