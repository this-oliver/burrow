# Chronicle

Automated backup tool for local and remote directories with comprehensive metadata tracking.

## Features

- 🗂️ **Local & Remote Backups**: Support for both local directories and remote servers via SSH/rsync
- 📝 **Comprehensive Metadata**: Each backup includes a detailed `BACKUP.md` file with source information
- 🔐 **SSH Key Authentication**: Secure remote connections with custom SSH keys
- 📊 **Detailed Reporting**: Success/failure tracking with comprehensive summary
- ⚙️ **Flexible Configuration**: JSON-based configuration with optional fields and sensible defaults

## Installation

Ensure the following dependencies are installed on your system:
- `jq` - JSON parsing
- `rsync` - Remote file synchronization
- `zip` - Archive creation

On macOS:
```bash
brew install jq rsync zip
```

On Ubuntu/Debian:
```bash
sudo apt-get install jq rsync zip
```

## Configuration

The backup tool uses a JSON configuration file to define backup jobs. By default, it looks for `config.json` in the current directory.

### Configuration Format

```json
{
  "backups": [
    {
      "name": "backup_name",
      "path": "/path/to/directory",
      "remote": {
        "ip": "192.168.1.100",
        "username": "remote_user",
        "port": 22,
        "key": "~/.ssh/backup_key"
      }
    }
  ]
}
```

### Field Descriptions

#### Required Fields
- **path** (string): Absolute or relative path to the directory to backup

#### Optional Fields
- **name** (string): Backup name used for filename and metadata. If omitted, uses the directory basename
- **remote** (object): Remote server configuration (required only for remote backups)

#### Remote Configuration Fields
- **ip** (string): IP address or hostname of remote server
- **username** (string): SSH username for remote server
- **port** (number): SSH port (default: 22)
- **key** (string): Path to SSH private key file (optional, uses default SSH keys if omitted)

## Usage

### Basic Usage

```bash
# Use default config.json
./entrypoint.sh

# Use custom configuration file
./entrypoint.sh --config /path/to/custom.json

# Show help
./entrypoint.sh --help
```

### Configuration Examples

#### Local Backup Only
```json
{
  "backups": [
    {
      "name": "documents",
      "path": "/home/user/documents"
    }
  ]
}
```

#### Remote Backup with SSH Key
```json
{
  "backups": [
    {
      "name": "server_logs",
      "path": "/var/log",
      "remote": {
        "ip": "192.168.1.100",
        "username": "backup_user",
        "port": 22,
        "key": "~/.ssh/backup_key"
      }
    }
  ]
}
```

#### Mixed Configuration (Local and Remote)
```json
{
  "backups": [
    {
      "name": "local_backup",
      "path": "./data"
    },
    {
      "name": "remote_backup",
      "path": "/opt/application",
      "remote": {
        "ip": "10.0.0.50",
        "username": "admin",
        "port": 2222
      }
    },
    {
      "path": "/etc/config"  // No name field - uses "config" as backup name
    }
  ]
}
```

## Output

### Filenames
- **With name field**: `{name}_{timestamp}.zip`
- **Without name field**: `{directory_basename}_{timestamp}.zip`
- **Example**: `application_logs_20240612_153045.zip`

### Archive Contents
Each backup archive includes:
- Original directory contents with preserved structure
- `BACKUP.md` file with comprehensive metadata

### Sample BACKUP.md
```markdown
# Backup Information

## Overview
- **Backup Name**: application_logs
- **Created**: 2024-06-12 15:30:45
- **Source Path**: /var/log/app

## Source Details
- **Type**: Remote
- **Server IP**: 192.168.1.100
- **Username**: backup_user
- **Port**: 22
- **Authentication Method**: SSH key (/home/user/.ssh/backup_key)
- **Original Path**: /var/log/app

## Archive Information
- **Archive Name**: application_logs_20240612_153045.zip
- **Archive Created**: 2024-06-12 15:30:45
- **Archive Size**: 1.2 GB
- **Total Files**: 1,247
- **Total Directories**: 89

## Backup Process
- **Backup Tool**: k8s-backup v1.0
- **Compression Method**: ZIP
- **Sync Method**: rsync over SSH
- **Timestamp**: 20240612_153045

## Notes
- This backup was created automatically by the k8s-backup tool
- Source directory: /var/log/app
- Backup name: application_logs
- Remote server: 192.168.1.100
```

## SSH Key Configuration

### Creating SSH Keys for Backups

1. Generate a dedicated SSH key for backup operations:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/backup_key -C "backup_key"
```

2. Copy the public key to remote servers:
```bash
ssh-copy-id -i ~/.ssh/backup_key.pub user@remote_server
```

3. Set proper permissions on the private key:
```bash
chmod 600 ~/.ssh/backup_key
```

### SSH Key Security
- Private keys should have permissions 600 or 400
- The tool will warn about insecure key permissions
- Use dedicated keys for backup operations
- Consider using SSH agents for additional security

## Error Handling

The tool provides detailed error messages for common issues:

- **Missing dependencies**: Install jq, rsync, zip
- **Configuration errors**: Invalid JSON, missing required fields
- **SSH key issues**: Key file not found, incorrect permissions
- **Remote connection failures**: Network issues, authentication problems
- **Directory not found**: Source path doesn't exist

## Exit Codes

- **0**: All backups completed successfully
- **1**: Some backups failed or configuration errors

## Troubleshooting

### SSH Key Not Found
```
✗ Backup 1: SSH key file '/path/to/key' not found
```
- Verify the key file path is correct
- Check file permissions (`ls -la /path/to/key`)
- Ensure the key file exists and is readable

### Remote Connection Failed
```
✗ Backup 1: Failed to sync remote directory '/path' from 192.168.1.100
```
- Verify network connectivity to remote server
- Check SSH credentials (username, port, key)
- Ensure the remote directory exists
- Test SSH connection manually: `ssh user@server ls /path`

### Directory Not Found
```
✗ Backup 1: Directory '/nonexistent/path' does not exist
```
- Verify the source directory path is correct
- Check directory permissions
- Use absolute paths when possible

## License

k8s-backup - Automated backup solution for local and remote directories.
