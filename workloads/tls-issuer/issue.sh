#!/bin/sh
# Issues / renews the TLS certificates formerly managed by cert-manager, using
# lego with the ACME DNS-01 challenge (Route53). Runs weekly as a CronJob and
# once as a bootstrap Job on first install. Idempotent: any certificate whose
# serving secret is still valid for more than RENEW_DAYS is left untouched.
#
# The set of certificates to maintain is passed in as JSON via CERTS_JSON, e.g.
#   [{ "secretName": "...", "domains": ["a", "*.a"],
#      "hostedZoneID": "Z...", "namespaces": ["admin", "default"] }, ...]
# Each certificate is minted once and written (identically) into every listed
# namespace. Cross-apex certs are supported by giving each its own hostedZoneID.
set -euo pipefail
set -f  # never glob-expand wildcard domains like *.cluster.cgamesplay.com

# alpine/k8s ships kubectl but not always openssl/jq; install on demand.
command -v openssl >/dev/null 2>&1 || apk add --no-cache openssl
command -v jq >/dev/null 2>&1 || apk add --no-cache jq

RENEW_DAYS="${RENEW_DAYS:-30}"
export AWS_REGION="${AWS_REGION:-eu-central-1}"

case "$TLS_ISSUER_MODE" in
  production)  SERVER=https://acme-v02.api.letsencrypt.org/directory ;;
  staging)     SERVER=https://acme-staging-v02.api.letsencrypt.org/directory ;;
  self-signed) SERVER= ;;
  *) echo "unknown TLS_ISSUER_MODE: ${TLS_ISSUER_MODE}" >&2; exit 1 ;;
esac

download_lego() {
  [ -x /tmp/lego ] && return 0
  wget -qO /tmp/lego.tgz \
    "https://github.com/go-acme/lego/releases/download/v${LEGO_VERSION}/lego_v${LEGO_VERSION}_linux_amd64.tar.gz"
  echo "${LEGO_SHA256}  /tmp/lego.tgz" | sha256sum -c -
  tar -xz -C /tmp -f /tmp/lego.tgz lego
  rm -f /tmp/lego.tgz
}

# $1 namespace, $2 secret name -> 0 if the existing cert is good for >RENEW_DAYS
cert_valid() {
  existing=$(kubectl -n "$1" get secret "$2" -o jsonpath='{.data.tls\.crt}' 2>/dev/null || true)
  [ -z "$existing" ] && return 1
  echo "$existing" | base64 -d | openssl x509 -checkend $((RENEW_DAYS * 86400)) -noout >/dev/null 2>&1
}

echo "$CERTS_JSON" | jq -c '.[]' | while IFS= read -r cert; do
  SECRET=$(echo "$cert"       | jq -r '.secretName')
  ZONE=$(echo "$cert"         | jq -r '.hostedZoneID')
  DOMAINS=$(echo "$cert"      | jq -r '.domains[]')
  NAMESPACES=$(echo "$cert"   | jq -r '.namespaces[]')
  FIRST_DOMAIN=$(echo "$cert" | jq -r '.domains[0]')
  FIRST_NS=$(echo "$cert"     | jq -r '.namespaces[0]')

  if cert_valid "$FIRST_NS" "$SECRET"; then
    echo "[$SECRET] valid > ${RENEW_DAYS}d in $FIRST_NS, nothing to do"
    continue
  fi

  if [ "$TLS_ISSUER_MODE" = self-signed ]; then
    SANS=$(echo "$DOMAINS" | sed 's/^/DNS:/' | paste -sd, -)
    openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
      -subj "/CN=${FIRST_DOMAIN}/O=200 OK, LLC" \
      -addext "subjectAltName=${SANS}" \
      -keyout /tmp/tls.key -out /tmp/tls.crt
    CRT=/tmp/tls.crt
    KEY=/tmp/tls.key
  else
    download_lego
    DOMAIN_ARGS=""
    for d in $DOMAINS; do DOMAIN_ARGS="$DOMAIN_ARGS --domains $d"; done
    rm -rf /tmp/lego-data && mkdir -p /tmp/lego-data
    AWS_HOSTED_ZONE_ID="$ZONE" /tmp/lego \
      --accept-tos --email "$ACME_EMAIL" --server "$SERVER" \
      --dns route53 $DOMAIN_ARGS --path /tmp/lego-data run
    # lego names cert files after the first domain, with '*' rewritten to '_'.
    SANITIZED=$(echo "$FIRST_DOMAIN" | sed 's/\*/_/g')
    CRT="/tmp/lego-data/certificates/${SANITIZED}.crt"
    KEY="/tmp/lego-data/certificates/${SANITIZED}.key"
  fi

  for ns in $NAMESPACES; do
    kubectl -n "$ns" create secret tls "$SECRET" \
      --cert="$CRT" --key="$KEY" \
      --dry-run=client -o yaml | kubectl apply -f -
    echo "[$SECRET] published to $ns"
  done
done
