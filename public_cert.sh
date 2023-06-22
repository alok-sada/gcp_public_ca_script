#!/bin/bash

# Load environment variables from .env file
source .env

# Set project configuration
gcloud config set project $PROJECT_ID

# Add IAM policy binding
if gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=user:$USER_EMAIL \
    --role=roles/publicca.externalAccountKeyCreator; then
  echo "------------------------------"
  echo "IAM policy binding successful."
else
  echo "------------------------------"
  echo "IAM policy binding failed."
  exit 1
fi

# Enable required service
gcloud services enable publicca.googleapis.com

# Check OS and install Certbot
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS (brew)
  if command -v certbot &> /dev/null; then
    echo "------------------------------"
    echo "Certbot already installed."
  else
    echo "------------------------------"
    echo "Installing Certbot..."
    brew install certbot
  fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  # Linux (apt-get)
  if command -v certbot &> /dev/null; then
    echo "------------------------------"
    echo "Certbot already installed."
  else
    echo "------------------------------"
    echo "Installing Certbot..."
    sudo apt-get install certbot
  fi
else
  echo "------------------------------"
  echo "Unsupported operating system."
  exit 1
fi

# Check OS and install OpenSSL if needed
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS (check if OpenSSL is installed)
  if ! command -v openssl &> /dev/null; then
      echo "----------------------------------------"
      echo "OpenSSL not found. Installing OpenSSL..."
      brew install openssl
  fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  # Linux (check if OpenSSL is installed)
  if ! command -v openssl &> /dev/null; then
      echo "----------------------------------------"
      echo "OpenSSL not found. Installing OpenSSL..."
      sudo apt-get install openssl
  fi
else
  echo "------------------------------"
  echo "Unsupported operating system."
  exit 1
fi

# Create public folder if it doesn't exist
public_folder=$ENV
if [ ! -d "$public_folder" ]; then
    mkdir -p "$public_folder"
fi

# Generate private key and CSR and save in public folder
openssl req -newkey rsa:4096 -nodes -keyout "$public_folder/private_${ENV}.key" -out "$public_folder/csr_${ENV}.pem" -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/OU=$ORG_UNIT/CN=$COMMON_NAME/emailAddress=$USER_EMAIL"

# Create an external account key and capture the output
key_output=$(gcloud alpha publicca external-account-keys create --format=json)

# Extract the values of b64MacKey and keyId from the output using jq
b64MacKey=$(echo "$key_output" | jq -r '.b64MacKey')
keyId=$(echo "$key_output" | jq -r '.keyId')

# Echo the extracted values
echo "b64MacKey: $b64MacKey"
echo "keyId: $keyId"

#Check existing certificates
if certbot show_account | grep -q "Could not find an existing account for server $ACME_SERVER."; then
  # No certificates found, register with Certbot
  certbot register \
    --email $USER_EMAIL \
    --no-eff-email \
    --server "$ACME_SERVER" \
    --eab-kid $keyId \
    --eab-hmac-key $b64MacKey \
    --agree-tos
else
  # Certificates found, unregister and then register with Certbot
  echo "D" | sudo certbot unregister --server "$ACME_SERVER" --non-interactive
  certbot register \
    --email $USER_EMAIL \
    --no-eff-email \
    --server "$ACME_SERVER" \
    --eab-kid $keyId \
    --eab-hmac-key $b64MacKey \
    --agree-tos
fi

# Generate .pem files which will create Certificate, Intermediate CA chain and a Full certificate chain

certbot certonly \
  --manual \
  --preferred-challenges "dns-01" \
  --server $ACME_SERVER \
  --csr "$public_folder/csr_${ENV}.pem" \
  --cert-path "$public_folder/certificate_${ENV}.pem" \
  --key-path "$public_folder/private_${ENV}.key" \
  --force-renewal \
  --rsa-key-size 4096

# moves the created .pem files in $ENV folder.  
  echo "----------------------------------------------"
  echo "Renaming and moving the file to ${ENV} folder."
  mv 0000_chain.pem $public_folder/intermediate_cert_${ENV}.pem
  mv 0001_chain.pem $public_folder/full_cert_${ENV}.pem
  
# Script Complete.  
  echo "----------------"
  echo "Script Complete."