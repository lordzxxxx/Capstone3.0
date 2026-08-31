#!/usr/bin/env bash
set -euo pipefail

# Vercel's Node build image does not provide Flutter. Keep the SDK version
# pinned so every Git deployment uses the same compiler as local release
# builds, while caching the download between Vercel builds when available.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_version="3.44.9"

system_flutter_version=""
if command -v flutter >/dev/null 2>&1; then
  system_flutter_version="$(flutter --version 2>/dev/null | sed -n 's/^Flutter \([0-9][0-9.]*\).*/\1/p' | head -1)"
fi

if [[ "${system_flutter_version}" != "${flutter_version}" ]]; then
  cache_root="${VERCEL_CACHE_DIR:-${repo_root}/node_modules/.cache}/ai-dsuhis/flutter"
  sdk_dir="${cache_root}/flutter-${flutter_version}"
  archive_path="${cache_root}/flutter_linux_${flutter_version}-stable.tar.xz"
  mkdir -p "${cache_root}"

  if [[ ! -x "${sdk_dir}/bin/flutter" ]]; then
    if [[ ! -f "${archive_path}" ]]; then
      curl --fail --location --retry 3 --retry-delay 2 \
        --connect-timeout 30 --max-time 1800 \
        --output "${archive_path}" \
        "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${flutter_version}-stable.tar.xz"
    fi

    extract_dir="$(mktemp -d "${cache_root}/extract.XXXXXX")"
    trap 'rm -rf "${extract_dir}"' EXIT
    tar -xJf "${archive_path}" -C "${extract_dir}"
    mv "${extract_dir}/flutter" "${sdk_dir}"
    trap - EXIT
    rm -rf "${extract_dir}"
  fi

  export PATH="${sdk_dir}/bin:${PATH}"
fi

if [[ -n "${VERCEL_GIT_COMMIT_SHA:-}" ]]; then
  export APP_VERSION="${VERCEL_GIT_COMMIT_SHA:0:7}"
fi

flutter --version
flutter config --no-analytics
flutter precache --web
flutter pub get

# The existing release command remains the single source of truth for the
# compiler flags, app-version file, APK artifact, and SPA output.
cd "${repo_root}"
npm run build:web:release
