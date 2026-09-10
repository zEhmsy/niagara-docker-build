#!/usr/bin/env bash
# Funzioni e default condivisi dagli script. Non eseguibile da solo.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die()  { echo "ERRORE: $*" >&2; exit 1; }
info() { echo ">> $*"; }

# Config: prima il file utente, poi quello del repo (il repo vince, cosi' un
# checkout dedicato puo' avere impostazioni proprie).
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

# 4.x -> "n4", tutto il resto -> "n5"
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
  command -v docker >/dev/null 2>&1 || die "docker non trovato nel PATH."
  docker info >/dev/null 2>&1 || die "il daemon Docker non risponde. Avvia Docker Desktop / dockerd."
}
