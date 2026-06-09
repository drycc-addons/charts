#!/usr/bin/env bash
set -euo pipefail

REGISTRY="${1:?Usage: push-charts.sh <registry>}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/_dist"

if [ -z "$(ls "${DIST_DIR}"/*.tgz 2>/dev/null)" ]; then
  echo "No charts to publish"
  exit 0
fi

echo "Pushing charts to ${REGISTRY}..."
for pkg in "${DIST_DIR}"/*.tgz; do
  helm push "$pkg" "oci://${REGISTRY}"
done
