#!/bin/bash
# Ubuntu build dependencies for native amd64 and arm64 Linux hosts.
set -euo pipefail

usage() { echo "Usage: bash $0 [--print]" >&2; }
case "${1:-}" in
  '') [ "$#" -eq 0 ] || { usage; exit 2; } ;;
  --print) [ "$#" -eq 1 ] || { usage; exit 2; } ;;
  *) usage; exit 2 ;;
esac

arch=$(dpkg --print-architecture)
packages=(
  build-essential clang flex bison g++ gawk gettext git
  libncurses-dev libssl-dev libelf-dev pkgconf
  python3 python3-setuptools python3-dev rsync swig unzip zlib1g-dev
  file wget zstd ca-certificates curl bzip2 xz-utils patch perl
)
case "$arch" in
  amd64) packages+=(gcc-multilib g++-multilib) ;;
  arm64) ;; # Native ARM64 GCC does not provide these multilib metapackages.
  *) echo "Unsupported build-host architecture: $arch (expected amd64 or arm64)" >&2; exit 1 ;;
esac

if [ "${1:-}" = --print ]; then
  printf '%s\n' "${packages[@]}"
  exit 0
fi

echo "Installing build dependencies for Ubuntu $arch"
if [ "$EUID" -eq 0 ]; then
  apt-get update
  apt-get install -y "${packages[@]}"
else
  sudo apt-get update
  sudo apt-get install -y "${packages[@]}"
fi
