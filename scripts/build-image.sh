#!/usr/bin/env bash
#
# Builds the Niagara build image from a Tridium installer.
# Run once per Niagara version.
#
#   ./scripts/build-image.sh 5.0.0.12
#   ./scripts/build-image.sh 4.15.3.28
#   ./scripts/build-image.sh 4.15.3.28 MyInstaller.zip   # explicit zip name
#
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
load_config
need_docker

VERSION="${1:-${NIAGARA_DEFAULT_VERSION}}"
INSTALLER_ARG="${2:-}"

if [ -z "${VERSION}" ]; then
  echo "usage: $0 <niagara-version> [installer-zip-name]" >&2
  echo "       e.g. $0 5.0.0.12   |   $0 4.15.3.28" >&2
  exit 2
fi

[ -d "${NIAGARA_INSTALLERS_DIR}" ] \
  || die "installer folder not found: ${NIAGARA_INSTALLERS_DIR}
       Create it and drop the Tridium zip in, or set NIAGARA_INSTALLERS_DIR."

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

# Installer lookup: explicit name if given, otherwise the glob from the config.
INSTALLER=""
if [ -n "${INSTALLER_ARG}" ]; then
  INSTALLER="${INSTALLER_ARG}"
else
  # The glob is deliberately unquoted: it is a pattern, not a filename. No `ls`
  # in a pipe either: under `pipefail` a glob with no match would kill the script
  # without printing anything.
  # shellcheck disable=SC2086
  for candidate in "${NIAGARA_INSTALLERS_DIR}"/${GLOB}; do
    if [ -f "${candidate}" ]; then
      INSTALLER="$(basename "${candidate}")"
      break
    fi
  done
fi

if [ -z "${INSTALLER}" ] || [ ! -f "${NIAGARA_INSTALLERS_DIR}/${INSTALLER}" ]; then
  echo "ERROR: no installer found for Niagara ${VERSION}." >&2
  echo "       looked for: ${NIAGARA_INSTALLERS_DIR}/${GLOB}" >&2
  echo "       available:" >&2
  # shellcheck disable=SC2012
  ls -1 "${NIAGARA_INSTALLERS_DIR}" 2>/dev/null | sed 's/^/          /' >&2 || true
  echo "       Pass the name explicitly: $0 ${VERSION} <name.zip>" >&2
  echo "       or adjust NIAGARA_N${FAMILY#n}_INSTALLER_GLOB in your config." >&2
  exit 1
fi

# The build context is the installer folder (often several GB): the
# .dockerignore next to the Dockerfile lets only the zip we need through. If your
# zip has a non-standard name, add its `!<pattern>` line in there.
IGNORE_FILE="${REPO_ROOT}/docker/${DOCKERFILE}.dockerignore"
[ -f "${IGNORE_FILE}" ] || die "missing ${IGNORE_FILE}"
grep -q -- "${INSTALLER%%[0-9]*}" "${IGNORE_FILE}" 2>/dev/null || \
  info "WARNING: '${INSTALLER}' does not look covered by ${IGNORE_FILE##*/}; if the build fails with 'file not found', add the line: !${INSTALLER}"

info "image     : ${IMAGE}"
info "installer : ${INSTALLER}"
info "platform  : ${NIAGARA_PLATFORM}"
info "the first run takes several minutes (JDK download + Niagara install)"

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
info "done: ${IMAGE}"
docker image inspect "${IMAGE}" --format '   size: {{.Size}} bytes'
echo
echo "   Now build a module:  ./scripts/nbuild.sh /path/to/project"
