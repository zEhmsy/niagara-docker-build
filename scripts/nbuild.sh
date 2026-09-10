#!/usr/bin/env bash
#
# Builda (e firma) un modulo Niagara dentro il container.
#
#   ./scripts/nbuild.sh <dir-progetto> [task gradle...]
#   ./scripts/nbuild.sh ~/dev/mioModulo                # -> gradle build
#   ./scripts/nbuild.sh ~/dev/mioModulo clean build
#   ./scripts/nbuild.sh ~/dev/mioModulo shell          # bash nel container
#
# La versione di Niagara viene dedotta dal `niagara_home` del gradle.properties
# del progetto; si puo' forzare con NIAGARA_VERSION=4.15.3.28.
#
# FIRMA: il profilo di signing sta in ~/.tridium/security/ dentro il container,
# montato da NIAGARA_SIGNING_HOME. Se la cartella e' vuota il plugin Tridium
# genera da solo una chiave nuova AD OGNI BUILD (e il Workbench va ri-fidato
# ogni volta). Usa `./scripts/signing.sh` per crearla o importare la tua.
#
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
load_config
need_docker

[ $# -ge 1 ] || { echo "uso: $0 <dir-progetto> [task gradle...]" >&2; exit 2; }

PROJECT_ARG="$1"; shift
PROJECT="$(cd "${PROJECT_ARG}" 2>/dev/null && pwd || true)"
[ -n "${PROJECT}" ] || die "progetto '${PROJECT_ARG}' non trovato."
[ -x "${PROJECT}/gradlew" ] || die "in ${PROJECT} non c'e' un ./gradlew eseguibile."

# --- versione ---------------------------------------------------------------
VERSION="${NIAGARA_VERSION:-}"
if [ -z "${VERSION}" ] && [ -f "${PROJECT}/gradle.properties" ]; then
  VERSION="$(grep -E '^[[:space:]]*niagara_home=' "${PROJECT}/gradle.properties" \
             | grep -oE '[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)"
fi
[ -n "${VERSION}" ] || [ -z "${NIAGARA_DEFAULT_VERSION}" ] || VERSION="${NIAGARA_DEFAULT_VERSION}"
[ -n "${VERSION}" ] || die "versione Niagara non deducibile da ${PROJECT}/gradle.properties.
       Forzala: NIAGARA_VERSION=<versione> $0 ..."

IMAGE="$(image_name "${VERSION}")"

docker image inspect "${IMAGE}" >/dev/null 2>&1 \
  || die "immagine ${IMAGE} assente. Lancia prima:
         ./scripts/build-image.sh ${VERSION}"

mkdir -p "${NIAGARA_SIGNING_HOME}"
if [ ! -d "${NIAGARA_SIGNING_HOME}/security" ]; then
  info "nessun profilo di firma in ${NIAGARA_SIGNING_HOME}/security"
  info "il plugin ne generera' uno nuovo (cert instabile tra i build)."
  info "per un certificato stabile: ./scripts/signing.sh init"
fi

# -t solo su terminale: in CI docker fallirebbe.
TTY_FLAGS=(-i)
[ -t 0 ] && [ -t 1 ] && TTY_FLAGS=(-i -t)

# Marker per riconoscere i jar prodotti da QUESTO build.
STAMP="$(mktemp -t nbuild.XXXXXX)"
trap 'rm -f "${STAMP}"' EXIT

CACHE_VOL="${NIAGARA_GRADLE_CACHE_PREFIX}-${VERSION%%.*}"

# --hostname fisso: il CN del cert autogenerato contiene l'hostname; con un
# hostname random il certificato cambierebbe a ogni creazione.
set +e
docker run --rm "${TTY_FLAGS[@]}" \
  --platform "${NIAGARA_PLATFORM}" \
  --hostname niagara-build \
  -v "${PROJECT}:/work" \
  -v "${NIAGARA_SIGNING_HOME}:/home/builder/.tridium" \
  -v "${CACHE_VOL}:/home/builder/.gradle" \
  -w /work \
  "${IMAGE}" "$@"
STATUS=$?
set -e
[ "${STATUS}" -ne 0 ] && exit "${STATUS}"

# --- raccolta artefatti -----------------------------------------------------
# Esclusi i jar che non sono il modulo (test, sorgenti, javadoc).
if [ -n "${NIAGARA_DIST_DIR}" ]; then
  if [ "${NIAGARA_DIST_FLAT}" = "1" ]; then
    DIST="${NIAGARA_DIST_DIR}"
  else
    DIST="${NIAGARA_DIST_DIR}/$(basename "${PROJECT}")"
  fi
else
  DIST="${PROJECT}/dist"
fi

FOUND=0
while IFS= read -r jar; do
  [ -z "${jar}" ] && continue
  [ "${FOUND}" -eq 0 ] && mkdir -p "${DIST}"
  FOUND=1
  cp -p "${jar}" "${DIST}/"
done < <(find "${PROJECT}" -type f -path "*/build/libs/*.jar" -newer "${STAMP}" \
           ! -name "*moduleTest*" ! -name "*-sources.jar" ! -name "*-javadoc.jar" \
           2>/dev/null | sort)

if [ "${FOUND}" -eq 1 ]; then
  echo
  info "jar in ${DIST}:"
  for j in "${DIST}"/*.jar; do
    [ -f "$j" ] || continue
    printf '   %-40s %8s KB\n' "$(basename "$j")" "$(( $(wc -c < "$j") / 1024 ))"
  done
fi
