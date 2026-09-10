#!/usr/bin/env bash
#
# Manages the code-signing profile used by the builds.
#
#   ./scripts/signing.sh init [--dname "CN=..."] [--alias name]
#       create a STABLE self-signed profile (does not change between builds)
#
#   ./scripts/signing.sh import --cert cert.pem --key key.pem [--chain ca.pem]
#       import YOUR own key/certificate pair (PEM) into the profile
#
#   ./scripts/signing.sh import --keystore mine.jceks --storepass xxx
#       reuse an existing JCEKS keystore (e.g. copied from Workbench)
#
#   ./scripts/signing.sh show          list what is in the keystore
#   ./scripts/signing.sh export-cert   export the .pem to trust in Workbench
#
# Everything lands in NIAGARA_SIGNING_HOME/security (default
# ~/.niagara-docker/tridium), which nbuild.sh mounts as ~/.tridium.
#
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
load_config

SEC="${NIAGARA_SIGNING_HOME}/security"
KS="${SEC}/niagara.signing.jceks"
XML="${SEC}/niagara.signing.xml"
: "${NIAGARA_SIGNING_ALIAS:=niagara4modules}"
: "${NIAGARA_SIGNING_VALIDITY:=1095}"
: "${NIAGARA_SIGNING_KEYSIZE:=3072}"
: "${KEYTOOL_IMAGE:=eclipse-temurin:21-jdk}"
: "${TMPDIR_SIGN:=/tmp}"

# keytool: the host one if available, otherwise from a container.
# -Duser.language=en: localized output would break the greps below.
# The "JCEKS uses a proprietary format" warning is expected — Niagara wants JCEKS.
keytool_run() {
  local rc=0
  if command -v keytool >/dev/null 2>&1; then
    keytool -J-Duser.language=en -J-Duser.country=US "$@" 2> >(drop_jceks_warning >&2) || rc=$?
  else
    need_docker
    docker run --rm -i --user "$(id -u):$(id -g)" \
      -v "${SEC}:${SEC}" -v "${TMPDIR_SIGN}:${TMPDIR_SIGN}" \
      -w "${SEC}" "${KEYTOOL_IMAGE}" \
      keytool -J-Duser.language=en -J-Duser.country=US "$@" 2> >(drop_jceks_warning >&2) || rc=$?
  fi
  return $rc
}

drop_jceks_warning() {
  grep -v -e 'proprietary format' -e '^Warning:$' -e '^$' || true
}

rand_pass() {
  if command -v openssl >/dev/null 2>&1; then openssl rand -hex 12
  else head -c 18 /dev/urandom | od -An -tx1 | tr -d ' \n'; fi
}

xml_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

write_profile_xml() {
  local storepass="$1" keypass="$2" dname="$3"
  local dname_esc; dname_esc="$(printf '%s' "${dname}" | xml_escape)"
  cat > "${XML}" <<XMLDOC
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<!DOCTYPE properties SYSTEM "http://java.sun.com/dtd/properties.dtd">
<properties>
<comment>Code Signing Properties - niagara-docker-build</comment>
<entry key="niagara.signing.profileType">com.tridium.gradle.plugins.signing.profile.LocalSigningProfile</entry>
<entry key="niagara.signing.storetype">JCEKS</entry>
<entry key="niagara.signing.storepass">${storepass}</entry>
<entry key="niagara.signing.keypass.${NIAGARA_SIGNING_ALIAS}">${keypass}</entry>
<entry key="niagara.signing.keyalg">RSA</entry>
<entry key="niagara.signing.keysize">${NIAGARA_SIGNING_KEYSIZE}</entry>
<entry key="niagara.signing.validity">${NIAGARA_SIGNING_VALIDITY}</entry>
<entry key="niagara.signing.dname">${dname_esc}</entry>
<entry key="niagara.signing.refresh">183</entry>
</properties>
XMLDOC
  chmod 600 "${XML}"
}

backup_existing() {
  if [ -e "${KS}" ] || [ -e "${XML}" ]; then
    local bak
    bak="${SEC}.bak.$(date +%Y%m%d%H%M%S)"
    info "existing profile moved to ${bak}"
    mv "${SEC}" "${bak}"
    mkdir -p "${SEC}"
  fi
}

read_prop() { # read_prop <key>
  [ -f "${XML}" ] || return 1
  sed -n "s@.*<entry key=\"$1\">\(.*\)</entry>.*@\1@p" "${XML}" | head -1
}

cmd_init() {
  local dname="" alias_arg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --dname) dname="$2"; shift 2 ;;
      --alias) alias_arg="$2"; shift 2 ;;
      *) die "unknown option: $1" ;;
    esac
  done
  [ -n "${alias_arg}" ] && NIAGARA_SIGNING_ALIAS="${alias_arg}"
  [ -n "${dname}" ] || dname="CN=$(id -un)@$(hostname -s 2>/dev/null || echo docker), OU=Niagara Module Signing, O=$(id -un), C=IT"

  mkdir -p "${SEC}"; chmod 700 "${SEC}"
  backup_existing
  mkdir -p "${SEC}"

  local storepass keypass
  storepass="$(rand_pass)"; keypass="${storepass}"

  TMPDIR_SIGN="${SEC}"
  keytool_run -genkeypair \
    -alias "${NIAGARA_SIGNING_ALIAS}" \
    -keyalg RSA -keysize "${NIAGARA_SIGNING_KEYSIZE}" \
    -validity "${NIAGARA_SIGNING_VALIDITY}" \
    -dname "${dname}" \
    -keystore "${KS}" -storetype JCEKS \
    -storepass "${storepass}" -keypass "${keypass}" \
    -ext "KeyUsage=digitalSignature" -ext "ExtendedKeyUsage=codeSigning"
  chmod 600 "${KS}"
  write_profile_xml "${storepass}" "${keypass}" "${dname}"

  info "profile created in ${SEC}"
  cmd_export_cert
}

# Tridium rejects certificates without the "Code Signing" Extended Key Usage:
# the build dies at `:<module>:jar` with
#   "Certificate for Niagara4Modules is not valid for code signing".
# Better to say so here than after minutes of compiling.
validate_codesign_cert() {
  local cert="$1" text
  text="$(openssl x509 -in "${cert}" -noout -text 2>/dev/null)" || die "cannot read PEM: ${cert}"
  if ! printf '%s' "${text}" | grep -A2 -i "Extended Key Usage" | grep -qi "Code Signing"; then
    if [ "${FORCE_IMPORT:-0}" = "1" ]; then
      info "WARNING: no Code Signing EKU, importing anyway (FORCE_IMPORT=1)."
      return 0
    fi
    cat >&2 <<MSG
ERROR: ${cert} has no "Code Signing" Extended Key Usage.
       Niagara refuses to sign with it and the build dies at :<module>:jar.
       The certificate needs:
         X509v3 Key Usage:          Digital Signature
         X509v3 Extended Key Usage: Code Signing
       If you issue it yourself, the short path is:
         ./scripts/signing.sh init --dname "CN=MyVendor, O=MyCo, C=IT"
       If it is a corporate certificate, ask the issuer to add the EKU.
       To import anyway: FORCE_IMPORT=1 $0 import ...
MSG
    exit 1
  fi
}

cmd_import() {
  local cert="" key="" chain="" keystore="" storepass="" alias_arg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --cert)      cert="$2"; shift 2 ;;
      --key)       key="$2"; shift 2 ;;
      --chain)     chain="$2"; shift 2 ;;
      --keystore)  keystore="$2"; shift 2 ;;
      --storepass) storepass="$2"; shift 2 ;;
      --alias)     alias_arg="$2"; shift 2 ;;
      *) die "unknown option: $1" ;;
    esac
  done
  [ -n "${alias_arg}" ] && NIAGARA_SIGNING_ALIAS="${alias_arg}"

  mkdir -p "${SEC}"; chmod 700 "${SEC}"

  if [ -n "${keystore}" ]; then
    [ -f "${keystore}" ] || die "keystore not found: ${keystore}"
    [ -n "${storepass}" ] || die "--keystore also requires --storepass"
    backup_existing
    cp "${keystore}" "${KS}"; chmod 600 "${KS}"
    write_profile_xml "${storepass}" "${storepass}" \
      "CN=imported, OU=Niagara Module Signing"
    info "keystore imported into ${KS}"
    cmd_show
    return
  fi

  if [ -z "${cert}" ] || [ -z "${key}" ]; then
    die "need --cert <file.pem> --key <file.pem> (or --keystore)"
  fi
  [ -f "${cert}" ] || die "certificate not found: ${cert}"
  [ -f "${key}"  ] || die "private key not found: ${key}"
  command -v openssl >/dev/null 2>&1 || die "openssl is required to convert the PEM files."
  validate_codesign_cert "${cert}"

  # Global on purpose: the EXIT trap fires outside this function, where a
  # `local` would no longer exist.
  TMPWORK="$(mktemp -d -t niagara-signing.XXXXXX)"
  local tmp="${TMPWORK}"
  TMPDIR_SIGN="${TMPWORK}"
  trap 'rm -rf "${TMPWORK}"' EXIT

  local pass; pass="$(rand_pass)"
  local certfile="${cert}"
  if [ -n "${chain}" ]; then
    cat "${cert}" "${chain}" > "${tmp}/full.pem"
    certfile="${tmp}/full.pem"
  fi

  # PEM -> PKCS12 -> JCEKS: keytool cannot import PEM files directly.
  openssl pkcs12 -export \
    -in "${certfile}" -inkey "${key}" \
    -name "${NIAGARA_SIGNING_ALIAS}" \
    -out "${tmp}/bundle.p12" -passout "pass:${pass}"

  backup_existing
  keytool_run -importkeystore \
    -srckeystore "${tmp}/bundle.p12" -srcstoretype PKCS12 -srcstorepass "${pass}" \
    -srcalias "${NIAGARA_SIGNING_ALIAS}" \
    -destkeystore "${KS}" -deststoretype JCEKS \
    -deststorepass "${pass}" -destkeypass "${pass}" \
    -destalias "${NIAGARA_SIGNING_ALIAS}" -noprompt
  chmod 600 "${KS}"

  local dname
  dname="$(openssl x509 -in "${cert}" -noout -subject 2>/dev/null | sed 's/^subject= *//' || echo "CN=imported")"
  write_profile_xml "${pass}" "${pass}" "${dname}"

  info "certificate imported into ${KS} (alias ${NIAGARA_SIGNING_ALIAS})"
  cmd_show
}

cmd_show() {
  [ -f "${KS}" ] || die "no keystore in ${KS}. Run: $0 init"
  local sp; sp="$(read_prop niagara.signing.storepass)" || die "missing ${XML}"
  TMPDIR_SIGN="${SEC}"
  keytool_run -list -v -keystore "${KS}" -storetype JCEKS -storepass "${sp}" \
    | grep -E "Alias name|Owner|Issuer|Valid from|Signature algorithm" || true
}

cmd_export_cert() {
  [ -f "${KS}" ] || die "no keystore in ${KS}. Run: $0 init"
  local sp alias_key out
  sp="$(read_prop niagara.signing.storepass)"
  alias_key="$(sed -n 's@.*<entry key="niagara.signing.keypass.\([^"]*\)">.*@\1@p' "${XML}" | head -1)"
  [ -n "${alias_key}" ] || alias_key="${NIAGARA_SIGNING_ALIAS}"
  out="${SEC}/${alias_key}-codesign.pem"
  TMPDIR_SIGN="${SEC}"
  keytool_run -exportcert -rfc \
    -alias "${alias_key}" -keystore "${KS}" -storetype JCEKS -storepass "${sp}" \
    -file "${out}"
  info "public certificate: ${out}"
  info "import it into the Workbench and Platform User Trust Stores,"
  info "otherwise the signed module will be rejected."
}

case "${1:-}" in
  init)        shift; cmd_init "$@" ;;
  import)      shift; cmd_import "$@" ;;
  show)        shift; cmd_show ;;
  export-cert) shift; cmd_export_cert ;;
  *)
    # Print the header block (comment lines after the shebang) as usage text,
    # so the two never drift apart.
    awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"
    exit 2 ;;
esac
