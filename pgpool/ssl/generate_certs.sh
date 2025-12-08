#!/bin/bash
# Script to generate self-signed SSL certificates for pgpool

CERT_DIR="$(dirname "$0")"
DAYS=3650  # 10 years
KEYSIZE=2048

echo "Generating SSL certificates for pgpool..."

# Generate private key
openssl genrsa -out "${CERT_DIR}/server.key" ${KEYSIZE}

# Generate self-signed certificate
openssl req -new -x509 -days ${DAYS} -key "${CERT_DIR}/server.key" -out "${CERT_DIR}/server.crt" \
  -subj "/C=US/ST=State/L=City/O=Organization/OU=IT/CN=pgpool"

# Generate CA certificate (optional, for client verification)
openssl req -new -x509 -days ${DAYS} -key "${CERT_DIR}/server.key" -out "${CERT_DIR}/root.crt" \
  -subj "/C=US/ST=State/L=City/O=Organization/OU=IT/CN=pgpool-ca"

# Set proper permissions
chmod 600 "${CERT_DIR}/server.key"
chmod 644 "${CERT_DIR}/server.crt"
chmod 644 "${CERT_DIR}/root.crt"

echo "SSL certificates generated successfully in ${CERT_DIR}"
echo "Files created:"
echo "  - server.key (private key)"
echo "  - server.crt (server certificate)"
echo "  - root.crt (CA certificate)"
