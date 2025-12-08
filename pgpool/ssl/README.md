# SSL Certificates for Pgpool

This directory contains SSL certificates for securing pgpool client connections.

## Generating Certificates

Run the script to generate self-signed certificates:

```bash
chmod +x generate_certs.sh
./generate_certs.sh
```

This will create:
- `server.key` - Private key (keep secure)
- `server.crt` - Server certificate
- `root.crt` - CA certificate (optional)

## Using Your Own Certificates

If you have your own SSL certificates, place them in this directory:
- Replace `server.key` with your private key
- Replace `server.crt` with your server certificate
- Replace `root.crt` with your CA certificate (if applicable)

Ensure proper permissions:
```bash
chmod 600 server.key
chmod 644 server.crt
chmod 644 root.crt
```

## Client Connection

Clients can connect using SSL:
```bash
psql "host=pgpool-host port=9999 dbname=mydb user=myuser sslmode=require"
```

SSL modes:
- `disable` - No SSL
- `allow` - Try SSL, fall back to non-SSL
- `prefer` - Try SSL first (default)
- `require` - Require SSL
- `verify-ca` - Require SSL and verify CA
- `verify-full` - Require SSL and verify hostname
