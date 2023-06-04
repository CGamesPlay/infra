# syntax=docker/dockerfile:1
FROM alpine:latest
ENV VAULT_ADDR=https://vault.cluster.cgamesplay.com/
ENV NOMAD_ADDR=https://nomad.cluster.cgamesplay.com/

ADD ca.crt /usr/local/share/vault.crt

RUN <<EOF
apk add --no-cache libcap vault nomad
setcap cap_ipc_lock= /usr/sbin/vault
cat /usr/local/share/vault.crt >> /etc/ssl/certs/ca-certificates.crt
EOF
