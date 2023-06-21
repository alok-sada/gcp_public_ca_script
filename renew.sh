#!/bin/bash

# Load environment variables from .env file
source .env

# Check the certificate expiration date
expiration_date=$(openssl x509 -in "$ENV/certificate_$ENV.pem" -noout -enddate | awk -F'=' '{print $2}')

if [[ "$(date -ju -f '%b %d %T %Y %Z' "$expiration_date" +%s)" -lt "$(date -u +%s)" ]]; then
  echo "Certificate has expired. Renewing..."
  # Run Certbot renewal
  certbot renew --force-renewal
else
  echo "Certificate is still valid. No renewal needed."
fi
