#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/_dist"

mkdir -p "${DIST_DIR}"

package_chart() {
  local chart_dir="$1"
  local label="$2"
  helm package -u "${chart_dir}" --destination "${DIST_DIR}" \
    --version "${CHART_VERSION}" --app-version "${APP_VERSION}" 2>/dev/null && \
    echo "    -> packaged: ${label}"
}

sync_chart_versions() {
  [ -z "${VERSION:-}" ] && return
  for f in "${ROOT_DIR}"/classes/files/*.yaml; do
    [ -f "$f" ] || continue
    sed -i "s/chartVersion: \".*\"/chartVersion: \"${VERSION}\"/" "$f"
    echo "    -> synced ${f#${ROOT_DIR}/} chartVersion to ${VERSION}"
  done
}

echo "Building all charts..."
sync_chart_versions

if [ -f "${ROOT_DIR}/classes/Chart.yaml" ]; then
  echo ">>> Building classes chart"
  package_chart "${ROOT_DIR}/classes" "classes"
fi

for addon_dir in "${ROOT_DIR}"/addons/*/; do
  [ -d "$addon_dir" ] || continue
  addon=$(basename "$addon_dir")
  if [ -f "${addon_dir}/Chart.yaml" ]; then
    echo ">>> Building addon chart: ${addon}"
    package_chart "$addon_dir" "addons/${addon}"
  fi
done

echo ""
echo "Build complete. Packages in ${DIST_DIR}:"
ls -1 "${DIST_DIR}/"*.tgz 2>/dev/null | sed 's/^/  /' || echo "  (none)"
