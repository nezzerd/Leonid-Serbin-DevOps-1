#!/usr/bin/env bash

set -euo pipefail

version="${1:-4.6.0}"
case "$(uname -s)" in
  Darwin) os="darwin" ;;
  Linux) os="linux" ;;
  *)
    echo "Unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

case "$(uname -m)" in
  arm64|aarch64) arch="arm64" ;;
  x86_64|amd64) arch="amd64" ;;
  *)
    echo "Unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

for command in curl unzip python3 basename; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required command is missing: $command" >&2
    exit 1
  }
done

if command -v shasum >/dev/null 2>&1; then
  sha256() { shasum -a 256 "$1" | awk '{ print $1 }'; }
elif command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$1" | awk '{ print $1 }'; }
else
  echo "Required command is missing: shasum or sha256sum" >&2
  exit 1
fi

filename="terraform-provider-docker_${version}_${os}_${arch}.zip"
base_url="https://github.com/kreuzwerker/terraform-provider-docker/releases/download/v${version}"
mirror="$HOME/.terraform.d/plugins"
target="${mirror}/registry.terraform.io/kreuzwerker/docker/${version}/${os}_${arch}"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

mkdir -p "$target"
if [[ $# -ge 2 ]]; then
  archive="$2"
  checksums="${3:-}"
  [[ "$(basename "$archive")" == "$filename" ]] || {
    echo "Expected archive name: $filename" >&2
    exit 1
  }
  [[ -f "$archive" && -n "$checksums" && -f "$checksums" ]] || {
    echo "Usage with local files: $0 VERSION PROVIDER_ZIP SHA256SUMS" >&2
    exit 1
  }
  cp "$archive" "${temporary}/${filename}"
  cp "$checksums" "${temporary}/SHA256SUMS"
else
  curl --fail --location --silent --show-error \
    "${base_url}/${filename}" \
    --output "${temporary}/${filename}"
  curl --fail --location --silent --show-error \
    "${base_url}/terraform-provider-docker_${version}_SHA256SUMS" \
    --output "${temporary}/SHA256SUMS"
fi

expected="$(awk -v file="$filename" '$2 == file { print $1 }' "${temporary}/SHA256SUMS")"
actual="$(sha256 "${temporary}/${filename}")"
if [[ -z "$expected" || "$expected" != "$actual" ]]; then
  echo "SHA-256 verification failed for ${filename}" >&2
  exit 1
fi

unzip -q -o "${temporary}/${filename}" -d "$target"
chmod +x "${target}"/terraform-provider-docker_v${version}*

mirror_json="$(python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$mirror")"
cli_config="$HOME/.terraformrc.dz1-docker"
cat > "$cli_config" <<EOF
provider_installation {
  filesystem_mirror {
    path = ${mirror_json}
  }
}
EOF

echo "Installed provider ${version} for ${os}_${arch}."
echo "Use this configuration for this project:"
echo "export TF_CLI_CONFIG_FILE=${cli_config}"
