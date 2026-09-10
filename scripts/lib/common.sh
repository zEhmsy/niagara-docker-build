#!/usr/bin/env bash
# Shared helpers and defaults. Not meant to be run on its own.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo ">> $*"; }

# Config: user file first, repo file second (the repo wins, so a dedicated
# checkout can carry its own settings).
load_config() {
  local user_conf="${XDG_CONFIG_HOME:-$HOME/.config}/niagara-docker-build/config"
  # shellcheck source=/dev/null
  [ -f "${user_conf}" ] && . "${user_conf}"
  # shellcheck source=/dev/null
  [ -f "${REPO_ROOT}/niagara-build.conf" ] && . "${REPO_ROOT}/niagara-build.conf"

  : "${NIAGARA_INSTALLERS_DIR:=${REPO_ROOT}/installers}"
  : "${NIAGARA_DEFAULT_VERSION:=}"
  : "${NIAGARA_IMAGE_PREFIX:=niagara-build}"
  : "${NIAGARA_SIGNING_HOME:=${HOME}/.niagara-docker/tridium}"
  : "${NIAGARA_DIST_DIR:=}"
  : "${NIAGARA_DIST_FLAT:=0}"
  : "${NIAGARA_PLATFORM:=linux/amd64}"
  : "${NIAGARA_N5_INSTALLER_GLOB:=Niagara_5_Debian-%VERSION%*.zip}"
  : "${NIAGARA_N4_INSTALLER_GLOB:=*N4*Linux_x64-%VERSION%*.zip}"
  : "${NIAGARA_N5_BRAND:=tridium}"
  : "${NIAGARA_N4_BRAND:=TridiumEMEA}"
  : "${NIAGARA_GRADLE_CACHE_PREFIX:=niagara-gradle-cache}"
  : "${JDK_URL_N5:=https://api.adoptium.net/v3/binary/latest/25/ga/linux/x64/jdk/hotspot/normal/eclipse}"
  : "${JDK_URL_N4:=https://api.adoptium.net/v3/binary/latest/8/ga/linux/x64/jdk/hotspot/normal/eclipse}"
}

# 4.x -> "n4", anything else -> "n5"
niagara_family() {
  case "$1" in
    4.*) echo n4 ;;
    *)   echo n5 ;;
  esac
}

image_name() { echo "${NIAGARA_IMAGE_PREFIX}:$1"; }

# "5.0.0.12" -> "5.0"
version_major_minor() { echo "$1" | cut -d. -f1,2; }

need_docker() {
  command -v docker >/dev/null 2>&1 || die "docker not found in PATH."
  docker info >/dev/null 2>&1 || die "the Docker daemon is not responding. Start Docker Desktop / dockerd."
}
