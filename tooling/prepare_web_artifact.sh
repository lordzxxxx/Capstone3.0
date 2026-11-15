#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${1:-${repo_root}/build/web}"
source_apk="${repo_root}/web/downloads/ai-dsuhis-bhw.apk"
target_dir="${output_dir}/downloads"

if [[ ! -f "${source_apk}" ]]; then
  echo "No BHW APK supplied; publishing the web/PWA release without an APK download." >&2
else
  mkdir -p "${target_dir}"
  cp "${source_apk}" "${target_dir}/ai-dsuhis-bhw.apk"
  echo "Copied BHW APK to ${target_dir}/ai-dsuhis-bhw.apk"
fi

version="${APP_VERSION:-$(git -C "${repo_root}" rev-parse --short HEAD 2>/dev/null || echo dev)}"
printf '{"version":"%s"}\n' "${version}" > "${output_dir}/app-version.json"
echo "Wrote web application version ${version}"
