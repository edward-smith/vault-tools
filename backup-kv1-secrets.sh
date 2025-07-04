#!/bin/bash

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-}"
VAULT_TOKEN="${VAULT_TOKEN:-}"
BACKUP_DIR="${BACKUP_DIR:-./vault-backup}"
SECRET_PATH="${SECRET_PATH:-secret/}"

if [[ -z "$VAULT_ADDR" ]]; then
    echo "Error: VAULT_ADDR environment variable must be set"
    exit 1
fi

if [[ -z "$VAULT_TOKEN" ]]; then
    echo "Error: VAULT_TOKEN environment variable must be set"
    exit 1
fi

mkdir -p "$BACKUP_DIR"

echo "Starting backup of KV1 secrets from path: $SECRET_PATH"
echo "Vault address: $VAULT_ADDR"
echo "Backup directory: $BACKUP_DIR"

backup_secret() {
    local secret_path="$1"
    local output_file="$2"
    
    echo "Backing up: $secret_path"
    
    if vault kv get -format=json "$secret_path" > "$output_file" 2>/dev/null; then
        echo "✓ Successfully backed up: $secret_path"
    else
        echo "✗ Failed to backup: $secret_path"
        rm -f "$output_file"
    fi
}

list_secrets_recursive() {
    local path="$1"
    local secrets
    
    if secrets=$(vault kv list -format=json "$path" 2>/dev/null); then
        echo "$secrets" | jq -r '.[]' | while read -r item; do
            if [[ "$item" == */ ]]; then
                list_secrets_recursive "$path$item"
            else
                local full_path="$path$item"
                local safe_path=$(echo "$full_path" | sed 's/[^a-zA-Z0-9/_-]/_/g')
                local output_file="$BACKUP_DIR/${safe_path}.json"
                
                mkdir -p "$(dirname "$output_file")"
                backup_secret "$full_path" "$output_file"
            fi
        done
    else
        echo "Warning: Could not list secrets at path: $path"
    fi
}

if ! command -v vault &> /dev/null; then
    echo "Error: vault CLI not found. Please install HashiCorp Vault CLI."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq not found. Please install jq for JSON processing."
    exit 1
fi

if ! vault status &> /dev/null; then
    echo "Error: Cannot connect to Vault server at $VAULT_ADDR"
    exit 1
fi

list_secrets_recursive "$SECRET_PATH"

echo "Backup completed! Files saved to: $BACKUP_DIR"