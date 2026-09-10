#!/usr/bin/env bash
#
# Costruisce l'immagine di build Niagara a partire da un installer Tridium.
# Da lanciare una volta per versione.
#
#   ./scripts/build-image.sh 5.0.0.12
#   ./scripts/build-image.sh 4.15.3.28
#   ./scripts/build-image.sh 4.15.3.28 MioInstaller.zip   # nome zip esplicito
#
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
load_config
need_docker

VERSION="${1:-${NIAGARA_DEFAULT_VERSION}}"
INSTALLER_ARG="${2:-}"

if [ -z "${VERSION}" ]; then
  echo "uso: $0 <versione-niagara> [nome-zip-installer]" >&2
  echo "     es. $0 5.0.0.12   |   $0 4.15.3.28" >&2
  exit 2
fi

[ -d "${NIAGARA_INSTALLERS_DIR}" ] \
  || die "cartella installer non trovata: ${NIAGARA_INSTALLERS_DIR}
       Creala e mettici lo zip Tridium, oppure imposta NIAGARA_INSTALLERS_DIR."

FAMILY="$(niagara_family "${VERSION}")"
MAJOR_MINOR="$(version_major_minor "${VERSION}")"
IMAGE="$(image_name "${VERSION}")"

if [ "${FAMILY}" = "n4" ]; then
  DOCKERFILE="Dockerfile.n4"
  GLOB="${NIAGARA_N4_INSTALLER_GLOB//%VERSION%/${VERSION}}"
  BUILD_ARGS=(
    --build-arg "JDK_URL=${JDK_URL_N4}"
    --build-arg "NIAGARA_BRAND=${NIAGARA_N4_BRAND}"
    --build-arg "NIAGARA_USER_HOME_SUBPATH=Niagara${MAJOR_MINOR}/${NIAGARA_N4_BRAND}"
  )
  INSTALLER_ARG_NAME=INSTALLER_ZIP
else
  DOCKERFILE="Dockerfile.n5"
  GLOB="${NIAGARA_N5_INSTALLER_GLOB//%VERSION%/${VERSION}}"
  BUILD_ARGS=(
    --build-arg "JDK_URL=${JDK_URL_N5}"
    --build-arg "NIAGARA_BRAND=${NIAGARA_N5_BRAND}"
    --build-arg "NIAGARA_USER_HOME_SUBPATH=Niagara/${NIAGARA_N5_BRAND}/${MAJOR_MINOR}"
  )
  INSTALLER_ARG_NAME=DEB_ZIP
fi

# Risoluzione dell'installer: nome esplicito, altrimenti glob dalla config.
if [ -n "${INSTALLER_ARG}" ]; then
  INSTALLER="${INSTALLER_ARG}"
else
  # glob volutamente non quotato: e' un pattern, non un nome file.
  # shellcheck disable=SC2012,SC2086
  INSTALLER="$(cd "${NIAGARA_INSTALLERS_DIR}" && ls -1 ${GLOB} 2>/dev/null | head -1 || true)"
fi

if [ -z "${INSTALLER}" ] || [ ! -f "${NIAGARA_INSTALLERS_DIR}/${INSTALLER}" ]; then
  echo "ERRORE: installer per Niagara ${VERSION} non trovato." >&2
  echo "        cercato: ${NIAGARA_INSTALLERS_DIR}/${GLOB}" >&2
  echo "        presenti:" >&2
  # shellcheck disable=SC2012
  ls -1 "${NIAGARA_INSTALLERS_DIR}" 2>/dev/null | sed 's/^/          /' >&2 || true
  echo "        Passa il nome esplicito: $0 ${VERSION} <nome.zip>" >&2
  echo "        oppure adatta NIAGARA_N${FAMILY#n}_INSTALLER_GLOB nella config." >&2
  exit 1
fi

# Il context e' la cartella installer (spesso alcuni GB): il .dockerignore
# accanto al Dockerfile lascia passare solo lo zip che serve. Se il tuo zip ha
# un nome fuori standard, aggiungi la sua riga `!<pattern>` li' dentro.
IGNORE_FILE="${REPO_ROOT}/docker/${DOCKERFILE}.dockerignore"
[ -f "${IGNORE_FILE}" ] || die "manca ${IGNORE_FILE}"
grep -q -- "${INSTALLER%%[0-9]*}" "${IGNORE_FILE}" 2>/dev/null || \
  info "ATTENZIONE: '${INSTALLER}' non sembra coperto da ${IGNORE_FILE##*/}; se il build fallisce con 'file not found', aggiungici la riga: !${INSTALLER}"

info "immagine   : ${IMAGE}"
info "installer  : ${INSTALLER}"
info "piattaforma: ${NIAGARA_PLATFORM}"
info "la prima volta richiede diversi minuti (download JDK + install Niagara)"

DOCKER_BUILDKIT=1 docker build \
  --platform "${NIAGARA_PLATFORM}" \
  -f "${REPO_ROOT}/docker/${DOCKERFILE}" \
  --build-arg "NIAGARA_VERSION=${VERSION}" \
  --build-arg "${INSTALLER_ARG_NAME}=${INSTALLER}" \
  "${BUILD_ARGS[@]}" \
  --build-arg "BUILDER_UID=$(id -u)" \
  --build-arg "BUILDER_GID=$(id -g)" \
  -t "${IMAGE}" \
  "${NIAGARA_INSTALLERS_DIR}"

echo
info "fatto: ${IMAGE}"
docker image inspect "${IMAGE}" --format '   size: {{.Size}} bytes'
echo
echo "   Ora builda un modulo:  ./scripts/nbuild.sh /path/al/progetto"
