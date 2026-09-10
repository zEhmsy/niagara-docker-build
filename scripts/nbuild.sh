#!/usr/bin/env bash
#
# Builds (and signs) a Niagara module inside the container.
#
#   ./scripts/nbuild.sh <project-dir> [gradle tasks...]
#   ./scripts/nbuild.sh ~/dev/myModule                # -> gradle build
#   ./scripts/nbuild.sh ~/dev/myModule clean build
#   ./scripts/nbuild.sh ~/dev/myModule shell          # bash inside the container
#
# The Niagara version comes from `niagara_home` in the project gradle.properties;
# override it with NIAGARA_VERSION=4.15.3.28.
#
# SIGNING: the signing profile lives in ~/.tridium/security/ inside the container,
# mounted from NIAGARA_SIGNING_HOME. If that folder is empty the Tridium plugin
# mints a new key ON EVERY BUILD (and Workbench asks you to trust it again every
# time). Use `./scripts/signing.sh` to create one or import your own.
#
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
load_config
need_docker

[ $# -ge 1 ] || { echo "usage: $0 <project-dir> [gradle tasks...]" >&2; exit 2; }

PROJECT_ARG="$1"; shift
PROJECT="$(cd "${PROJECT_ARG}" 2>/dev/null && pwd)" || PROJECT=""
[ -n "${PROJECT}" ] || die "project '${PROJECT_ARG}' not found."
[ -x "${PROJECT}/gradlew" ] || die "no executable ./gradlew in ${PROJECT}."

# --- version ---------------------------------------------------------------
VERSION="${NIAGARA_VERSION:-}"
if [ -z "${VERSION}" ] && [ -f "${PROJECT}/gradle.properties" ]; then
  VERSION="$(grep -E '^[[:space:]]*niagara_home=' "${PROJECT}/gradle.properties" \
             | grep -oE '[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)"
fi
[ -n "${VERSION}" ] || [ -z "${NIAGARA_DEFAULT_VERSION}" ] || VERSION="${NIAGARA_DEFAULT_VERSION}"
[ -n "${VERSION}" ] || die "cannot derive the Niagara version from ${PROJECT}/gradle.properties.
       Set it explicitly: NIAGARA_VERSION=<version> $0 ..."

IMAGE="$(image_name "${VERSION}")"

docker image inspect "${IMAGE}" >/dev/null 2>&1 \
  || die "image ${IMAGE} is missing. Build it first:
         ./scripts/build-image.sh ${VERSION}"

mkdir -p "${NIAGARA_SIGNING_HOME}"
if [ ! -d "${NIAGARA_SIGNING_HOME}/security" ]; then
  info "no signing profile in ${NIAGARA_SIGNING_HOME}/security"
  info "the plugin will mint a new one (certificate changes every build)."
  info "for a stable certificate: ./scripts/signing.sh init"
fi

# -t only on a real terminal: docker would fail in CI.
TTY_FLAGS=(-i)
[ -t 0 ] && [ -t 1 ] && TTY_FLAGS=(-i -t)

# Marker used to tell which jars came out of THIS build.
STAMP="$(mktemp -t nbuild.XXXXXX)"
trap 'rm -f "${STAMP}"' EXIT

CACHE_VOL="${NIAGARA_GRADLE_CACHE_PREFIX}-${VERSION%%.*}"

# Fixed --hostname: the CN of an auto-generated certificate contains the
# hostname, so a random one would change the certificate every time.
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

# --- artifact collection -----------------------------------------------------
# Skip the jars that are not the module itself (tests, sources, javadoc).
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
  info "jars in ${DIST}:"
  for j in "${DIST}"/*.jar; do
    [ -f "$j" ] || continue
    printf '   %-40s %8s KB\n' "$(basename "$j")" "$(( $(wc -c < "$j") / 1024 ))"
  done
fi
