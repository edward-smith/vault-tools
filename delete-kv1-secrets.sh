#!/bin/bash

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-}"
VAULT_TOKEN="${VAULT_TOKEN:-}"
SECRET_PATH="${SECRET_PATH:-secret/}"
BACKUP_DIR="${BACKUP_DIR:-./vault-backup}"
DRY_RUN="${DRY_RUN:-true}"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

if [[ -z "$VAULT_ADDR" ]]; then
    echo -e "${RED}Error: VAULT_ADDR environment variable must be set${NC}"
    exit 1
fi

if [[ -z "$VAULT_TOKEN" ]]; then
    echo -e "${RED}Error: VAULT_TOKEN environment variable must be set${NC}"
    exit 1
fi

if ! command -v vault &> /dev/null; then
    echo -e "${RED}Error: vault CLI not found. Please install HashiCorp Vault CLI.${NC}"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq not found. Please install jq for JSON processing.${NC}"
    exit 1
fi

if ! vault status &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Vault server at $VAULT_ADDR${NC}"
    exit 1
fi

verify_backup() {
    local secret_path="$1"
    local safe_path=$(echo "$secret_path" | sed 's/[^a-zA-Z0-9/_-]/_/g')
    local backup_file="$BACKUP_DIR/${safe_path}.json"
    
    if [[ ! -f "$backup_file" ]]; then
        echo -e "${RED}Error: Backup file not found: $backup_file${NC}"
        return 1
    fi
    
    if ! jq empty "$backup_file" 2>/dev/null; then
        echo -e "${RED}Error: Invalid JSON in backup file: $backup_file${NC}"
        return 1
    fi
    
    return 0
}

delete_secret() {
    local secret_path="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN] Would delete: $secret_path${NC}"
        return 0
    fi
    
    if ! verify_backup "$secret_path"; then
        echo -e "${RED}Skipping deletion of $secret_path - backup verification failed${NC}"
        return 1
    fi
    
    echo "Deleting: $secret_path"
    
    if vault kv delete "$secret_path" 2>/dev/null; then
        echo -e "${GREEN}✓ Successfully deleted: $secret_path${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to delete: $secret_path${NC}"
        return 1
    fi
}

list_secrets_for_deletion() {
    local path="$1"
    local secrets
    
    if secrets=$(vault kv list -format=json "$path" 2>/dev/null); then
        echo "$secrets" | jq -r '.[]' | while read -r item; do
            if [[ "$item" == */ ]]; then
                list_secrets_for_deletion "$path$item"
            else
                local full_path="$path$item"
                delete_secret "$full_path"
            fi
        done
    else
        echo -e "${YELLOW}Warning: Could not list secrets at path: $path${NC}"
    fi
}

echo -e "${YELLOW}===========================================${NC}"
echo -e "${YELLOW}    VAULT SECRET DELETION SCRIPT${NC}"
echo -e "${YELLOW}===========================================${NC}"
echo
echo "Vault address: $VAULT_ADDR"
echo "Secret path: $SECRET_PATH"
echo "Backup directory: $BACKUP_DIR"
echo "Dry run mode: $DRY_RUN"
echo

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}Running in DRY RUN mode - no secrets will be deleted${NC}"
    echo -e "${YELLOW}Set DRY_RUN=false to actually delete secrets${NC}"
    echo
else
    echo -e "${RED}WARNING: This will permanently delete all secrets under $SECRET_PATH${NC}"
    echo -e "${RED}Make sure you have verified your backups before proceeding!${NC}"
    echo
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        echo -e "${RED}Error: Backup directory does not exist: $BACKUP_DIR${NC}"
        echo "Please run the backup script first!"
        exit 1
    fi
    
    echo -e "${YELLOW}Do you want to continue? Type 'DELETE_SECRETS' to confirm:${NC}"
    read -r confirmation
    
    if [[ "$confirmation" != "DELETE_SECRETS" ]]; then
        echo "Deletion cancelled."
        exit 0
    fi
    
    echo
    echo -e "${YELLOW}Final confirmation: Are you absolutely sure? (y/N):${NC}"
    read -r final_confirm
    
    if [[ "$final_confirm" != "y" && "$final_confirm" != "Y" ]]; then
        echo "Deletion cancelled."
        exit 0
    fi
fi

echo
echo "Starting deletion process..."
echo

list_secrets_for_deletion "$SECRET_PATH"

echo
if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${GREEN}Dry run completed!${NC}"
    echo -e "${YELLOW}To actually delete secrets, run: DRY_RUN=false ./delete-kv1-secrets.sh${NC}"
else
    echo -e "${GREEN}Deletion process completed!${NC}"
fi