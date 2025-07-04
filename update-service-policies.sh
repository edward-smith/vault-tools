#!/bin/bash

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-}"
VAULT_TOKEN="${VAULT_TOKEN:-}"
SERVICE_PATH="${SERVICE_PATH:-service/}"
DRY_RUN="${DRY_RUN:-true}"
BACKUP_DIR="${BACKUP_DIR:-./policy-backup}"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
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

mkdir -p "$BACKUP_DIR"

extract_service_name() {
    local policy_name="$1"
    local service_name=""
    
    if [[ "$policy_name" =~ ^service/(.+)$ ]]; then
        service_name="${BASH_REMATCH[1]}"
    elif [[ "$policy_name" =~ ^(.+)-service$ ]]; then
        service_name="${BASH_REMATCH[1]}"
    else
        service_name="$policy_name"
    fi
    
    echo "$service_name"
}

remove_secret_references() {
    local policy_content="$1"
    
    # Remove entire path blocks that reference secret/
    echo "$policy_content" | awk '
    BEGIN { in_secret_block = 0; block_content = ""; brace_count = 0 }
    /^[[:space:]]*path[[:space:]]*"secret\/[^"]*"[[:space:]]*\{/ {
        in_secret_block = 1
        brace_count = 1
        next
    }
    in_secret_block == 1 {
        for (i = 1; i <= length($0); i++) {
            char = substr($0, i, 1)
            if (char == "{") brace_count++
            if (char == "}") brace_count--
        }
        if (brace_count == 0) {
            in_secret_block = 0
        }
        next
    }
    in_secret_block == 0 { print }
    '
}

add_aws_dmz_capability() {
    local policy_content="$1"
    local service_name="$2"
    
    # Only add AWS DMZ block if it doesn't already exist
    if ! echo "$policy_content" | grep -q "aws_dmz/creds/${service_name}"; then
        local aws_dmz_block="
path \"aws_dmz/creds/${service_name}\" {
  capabilities = [\"read\"]
}"
        
        # Ensure there's proper spacing
        if [[ -n "$policy_content" ]]; then
            echo "$policy_content"
            echo "$aws_dmz_block"
        else
            echo "$aws_dmz_block"
        fi
    else
        echo "$policy_content"
    fi
}

backup_policy() {
    local policy_name="$1"
    local policy_content="$2"
    local backup_file="$BACKUP_DIR/${policy_name//\//_}.hcl"
    
    mkdir -p "$(dirname "$backup_file")"
    echo "$policy_content" > "$backup_file"
    echo -e "${GREEN}✓ Backed up policy to: $backup_file${NC}"
}

process_policy() {
    local policy_name="$1"
    
    echo -e "${BLUE}Processing policy: $policy_name${NC}"
    
    local original_policy
    if ! original_policy=$(vault policy read "$policy_name" 2>/dev/null); then
        echo -e "${RED}✗ Failed to read policy: $policy_name${NC}"
        return 1
    fi
    
    local service_name
    service_name=$(extract_service_name "$policy_name")
    echo -e "${BLUE}  Service name: $service_name${NC}"
    
    backup_policy "$policy_name" "$original_policy"
    
    local modified_policy
    modified_policy=$(remove_secret_references "$original_policy")
    modified_policy=$(add_aws_dmz_capability "$modified_policy" "$service_name")
    
    # Validate the modified policy isn't empty or malformed
    if [[ -z "$modified_policy" ]] || [[ "$modified_policy" =~ ^[[:space:]]*$ ]]; then
        echo -e "${RED}✗ Error: Modified policy is empty for: $policy_name${NC}"
        return 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN] Would update policy: $policy_name${NC}"
        echo -e "${YELLOW}Modified policy content:${NC}"
        echo "----------------------------------------"
        echo "$modified_policy"
        echo "----------------------------------------"
        echo
    else
        echo "Updating policy: $policy_name"
        
        # Write to temporary file first to validate
        local temp_file=$(mktemp)
        echo "$modified_policy" > "$temp_file"
        
        if vault policy write "$policy_name" "$temp_file"; then
            echo -e "${GREEN}✓ Successfully updated policy: $policy_name${NC}"
            rm -f "$temp_file"
        else
            echo -e "${RED}✗ Failed to update policy: $policy_name${NC}"
            echo -e "${RED}Policy content that failed:${NC}"
            echo "----------------------------------------"
            cat "$temp_file"
            echo "----------------------------------------"
            rm -f "$temp_file"
            return 1
        fi
    fi
    
    return 0
}

list_service_policies() {
    local policies
    if ! policies=$(vault policy list -format=json 2>/dev/null); then
        echo -e "${RED}Error: Failed to list policies${NC}"
        exit 1
    fi
    
    echo "$policies" | jq -r '.[]' | while read -r policy; do
        if [[ "$policy" == service/* ]] || [[ "$policy" == *-service ]]; then
            process_policy "$policy"
        fi
    done
}

echo -e "${YELLOW}===========================================${NC}"
echo -e "${YELLOW}    VAULT POLICY UPDATE SCRIPT${NC}"
echo -e "${YELLOW}===========================================${NC}"
echo
echo "Vault address: $VAULT_ADDR"
echo "Service path pattern: $SERVICE_PATH"
echo "Backup directory: $BACKUP_DIR"
echo "Dry run mode: $DRY_RUN"
echo

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}Running in DRY RUN mode - no policies will be modified${NC}"
    echo -e "${YELLOW}Set DRY_RUN=false to actually update policies${NC}"
    echo
else
    echo -e "${RED}WARNING: This will modify all service policies${NC}"
    echo -e "${RED}Make sure you have reviewed the changes before proceeding!${NC}"
    echo
    
    echo -e "${YELLOW}Changes that will be made:${NC}"
    echo "1. Remove all references to 'secret/' paths"
    echo "2. Add read capability to 'aws_dmz/creds/<service-name>'"
    echo
    
    echo -e "${YELLOW}Do you want to continue? Type 'UPDATE_POLICIES' to confirm:${NC}"
    read -r confirmation
    
    if [[ "$confirmation" != "UPDATE_POLICIES" ]]; then
        echo "Policy update cancelled."
        exit 0
    fi
fi

echo
echo "Starting policy update process..."
echo

list_service_policies

echo
if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${GREEN}Dry run completed!${NC}"
    echo -e "${YELLOW}To actually update policies, run: DRY_RUN=false ./update-service-policies.sh${NC}"
else
    echo -e "${GREEN}Policy update process completed!${NC}"
    echo -e "${BLUE}Policy backups saved to: $BACKUP_DIR${NC}"
fi