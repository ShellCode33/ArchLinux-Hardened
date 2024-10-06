#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root using sudo"
  exit 1
fi

copy_if_different() {
  from="$1"
  to="$2"

  if grep username_placeholder "$from" &>/dev/null; then
    sha1from="$(sed "s/username_placeholder/$SUDO_USER/g" "$from" | sha1sum | awk '{print $1}' || true)"
  else
    sha1from="$(sha1sum "$from" 2>/dev/null | awk '{print $1}' || true)"
  fi

  sha1to="$(sha1sum "$to" 2>/dev/null | awk '{print $1}' || true)"

  if [ "$sha1from" != "$sha1to" ]; then
    mkdir -p "$(dirname "$to")"
    if cp --interactive "$from" "$to"; then
      sed -i "s/username_placeholder/$SUDO_USER/g" "$to"
      echo "$from -> $to"
    fi
  fi
}

export -f copy_if_different

find rootfs -type f ! -name "packages-*" -exec bash -c 'file="$1"; dest="/${file#rootfs/}"; copy_if_different "$file" "$dest"' shell {} \;
