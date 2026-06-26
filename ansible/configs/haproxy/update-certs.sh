#!/bin/bash

DOMAINS_FILE="/etc/pki/myca/domains.txt"
CA_DIR="/etc/pki/myca"

if [ ! -f "$DOMAINS_FILE" ]; then
    echo "Erro: $DOMAINS_FILE não encontrado."
    exit 1
fi

SAN=$(awk NF "$DOMAINS_FILE" | awk '{printf "DNS:%s,", $0}' | sed 's/,$//')
PRIMARY_DOMAIN=$(awk 'NR==1' "$DOMAINS_FILE")

echo "Gerando novo certificado para: $SAN"

openssl req -new -key "$CA_DIR/private/internal.key" \
  -out "$CA_DIR/internal.csr" \
  -subj "/CN=$PRIMARY_DOMAIN/O=Home Lab/C=BR"

cat > "$CA_DIR/internal.ext" << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=$SAN
EOF

openssl x509 -req -days 825 -in "$CA_DIR/internal.csr" \
  -CA "$CA_DIR/certs/ca.crt" -CAkey "$CA_DIR/private/ca.key" \
  -CAcreateserial -out "$CA_DIR/certs/internal.crt" \
  -extfile "$CA_DIR/internal.ext"

mkdir -p /etc/haproxy/certs
cat "$CA_DIR/certs/internal.crt" "$CA_DIR/private/internal.key" > /etc/haproxy/certs/internal.pem
chmod 600 /etc/haproxy/certs/internal.pem

rm -f "$CA_DIR/internal.csr" "$CA_DIR/internal.ext"
