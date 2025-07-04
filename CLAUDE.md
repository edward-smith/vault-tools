# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a collection of bash scripts and tools for managing HashiCorp Vault clusters. The repository focuses on defensive security operations, particularly backup and management utilities for Vault secrets.

## Architecture

The project is structured as a simple collection of standalone bash scripts, each designed for specific Vault management tasks:

- `backup-kv1-secrets.sh`: Recursively backs up all KV1 secrets from a Vault cluster to JSON files
- `delete-kv1-secrets.sh`: Safely deletes all KV1 secrets under a path after verifying backups exist

## Dependencies

Scripts require the following tools to be installed:

- HashiCorp Vault CLI (`vault`)
- `jq` for JSON processing
- Standard bash utilities

## Environment Variables

Scripts use these environment variables:

- `VAULT_ADDR`: Vault server URL (required)
- `VAULT_TOKEN`: Vault authentication token (required)
- `BACKUP_DIR`: Custom backup directory (optional, defaults to `./vault-backup`)
- `SECRET_PATH`: Custom secret path to backup/delete (optional, defaults to `secret/`)
- `DRY_RUN`: Set to `false` to actually delete secrets (defaults to `true`)

## Script Usage

All scripts are designed to be run directly from the command line after setting required environment variables:

```bash
export VAULT_ADDR="https://your-vault-server"
export VAULT_TOKEN="your-vault-token"
./backup-kv1-secrets.sh
```

## Security Considerations

- All scripts are designed for defensive security purposes only
- Scripts handle Vault authentication tokens through environment variables
- Backup files contain sensitive data and should be secured appropriately
- Scripts include validation to ensure Vault connectivity before operation
