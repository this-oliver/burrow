#!/usr/bin/env bash
# usage: ./entrypoint.sh [--config /path/to/config.json]
# Backups up directories based on JSON configuration file.
# Defaults to config.json in current directory.

set -euo pipefail

# Global variables for tracking backup results
declare -a BACKUP_RESULTS
declare -i TOTAL_BACKUPS=0
declare -i SUCCESSFUL_BACKUPS=0
declare -i FAILED_BACKUPS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Path utility functions
to_absolute_path() {
    local path="$1"
    local base_dir="$2"

    # Already absolute
    if [[ "$path" = /* ]]; then
        echo "$path"
    # Tilde expansion
    elif [[ "$path" =~ ^~ ]]; then
        echo "${HOME}${path:1}"
    # Relative to base directory
    else
        echo "$base_dir/$path"
    fi
}

get_config_dir() {
    if [[ -f "$CONFIG_FILE" ]]; then
        dirname "$(realpath "$CONFIG_FILE")"
    else
        echo "$(pwd)"  # Fallback for missing config
    fi
}

# 1. Check for required dependencies
check_dependencies() {
    local missing_deps=()

    for cmd in jq rsync zip; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${RED}Error: Missing required dependencies: ${missing_deps[*]}${NC}"
        echo "Please install the missing tools and try again."
        exit 1
    fi
}

# 2. Parse command line arguments
parse_arguments() {
    CONFIG_FILE="config.json"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --config|-c)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [--config /path/to/config.json]"
                echo "  --config, -c    Path to configuration file (default: config.json)"
                echo "  --help, -h      Show this help message"
                exit 0
                ;;
            *)
                echo -e "${RED}Error: Unknown argument '$1'${NC}"
                echo "Use --help for usage information."
                exit 1
                ;;
        esac
    done

    # Convert config path to absolute if it exists
    if [[ -f "$CONFIG_FILE" ]]; then
        CONFIG_FILE=$(realpath "$CONFIG_FILE")
    fi
}

# 3. Load and validate configuration
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}Error: Configuration file '$CONFIG_FILE' not found.${NC}"
        exit 1
    fi

    # Validate JSON structure
    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
        echo -e "${RED}Error: Configuration file is not valid JSON.${NC}"
        exit 1
    fi

    # Check if backups array exists
    if ! jq -e '.backups' "$CONFIG_FILE" &>/dev/null; then
        echo -e "${RED}Error: Configuration file must contain a 'backups' array.${NC}"
        exit 1
    fi

    # Get number of backups
    TOTAL_BACKUPS=$(jq '.backups | length' "$CONFIG_FILE")

    if [[ $TOTAL_BACKUPS -eq 0 ]]; then
        echo -e "${YELLOW}Warning: No backups configured in '$CONFIG_FILE'.${NC}"
        exit 0
    fi

    echo "Using configuration file: $CONFIG_FILE"
    echo "Found $TOTAL_BACKUPS backup configuration(s) in '$CONFIG_FILE'."
}

# 4. Process individual backup
process_backup() {
    local backup_index="$1"
    local backup_config
    backup_config=$(jq -c ".backups[$backup_index]" "$CONFIG_FILE")

    # Get absolute paths for resolution
    local config_dir
    config_dir=$(get_config_dir)

    # Extract required fields
    local name path
    name=$(echo "$backup_config" | jq -r '.name')
    path=$(echo "$backup_config" | jq -r '.path')

    # Extract optional remote fields
    local remote_ip username port key
    remote_ip=$(echo "$backup_config" | jq -r '.remote.ip // empty')
    username=$(echo "$backup_config" | jq -r '.remote.username // empty')
    port=$(echo "$backup_config" | jq -r '.remote.port // "22"')
    key=$(echo "$backup_config" | jq -r '.remote.key // empty')

    # Validate required path field
    if [[ -z "$path" || "$path" == "null" ]]; then
        local result="✗ Backup $((backup_index + 1)): Missing required 'path' field"
        BACKUP_RESULTS+=("$result")
        echo -e "${RED}$result${NC}"
        ((FAILED_BACKUPS++))
        return 1
    fi

    # Convert to absolute paths
    local absolute_path absolute_key
    absolute_path=$(to_absolute_path "$path" "$config_dir")
    if [[ -n "$key" && "$key" != "null" ]]; then
        absolute_key=$(to_absolute_path "$key" "$HOME")
    fi

    # Make name optional with fallback to absolute path basename
    if [[ -z "$name" || "$name" == "null" ]]; then
        name=$(basename "$absolute_path")
    fi

    echo -e "${YELLOW}Processing backup $((backup_index + 1))/$TOTAL_BACKUPS: $name ('$path' → '$absolute_path')${NC}"

    # Determine backup type and execute
    if [[ -n "$remote_ip" && "$remote_ip" != "null" ]]; then
        backup_remote_directory "$name" "$path" "$absolute_path" "$remote_ip" "$username" "$port" "$absolute_key" "$((backup_index + 1))"
    else
        backup_local_directory "$name" "$path" "$absolute_path" "$((backup_index + 1))"
    fi
}

# 5. Generate backup metadata file
generate_backup_metadata() {
    local name="$1"
    local original_path="$2"     # Original path from config
    local absolute_path="$3"      # Resolved absolute path
    local backup_type="$4"
    local remote_info="$5"
    local key_info="$6"
    local zip_name="$7"
    local source_dir="$8"
    local metadata_file="$source_dir/BACKUP.md"

    # Calculate archive statistics
    local file_count dir_count archive_size timestamp
    file_count=$(find "$source_dir" -type f | wc -l | tr -d ' ')
    dir_count=$(find "$source_dir" -type d | wc -l | tr -d ' ')
    archive_size=$(du -sh "$source_dir" | cut -f1)
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Create BACKUP.md content
    cat > "$metadata_file" << EOF
# Backup Information

## Overview
- **Backup Name**: $name
- **Created**: $timestamp
- **Source Path**: $original_path
- **Absolute Path**: $absolute_path

## Source Details
- **Type**: $backup_type
EOF

    # Add remote information if applicable
    if [[ "$backup_type" == "Remote" ]]; then
        cat >> "$metadata_file" << EOF
- **Server IP**: $remote_info
- **Username**: $(echo "$backup_config" | jq -r '.remote.username // "N/A"')
- **Port**: $(echo "$backup_config" | jq -r '.remote.port // "22"')
- **Authentication Method**: $key_info
- **Original Path**: $original_path
- **Remote Absolute Path**: $absolute_path
EOF
    else
        cat >> "$metadata_file" << EOF
- **Local Path**: $original_path
- **Absolute Path**: $absolute_path
EOF
    fi

    # Add archive information
    cat >> "$metadata_file" << EOF

## Archive Information
- **Archive Name**: $zip_name
- **Archive Created**: $timestamp
- **Archive Size**: $archive_size
- **Total Files**: $file_count
- **Total Directories**: $dir_count

## Backup Process
- **Backup Tool**: k8s-backup v1.0
- **Compression Method**: ZIP
EOF

    if [[ "$backup_type" == "Remote" ]]; then
        echo "- **Sync Method**: rsync over SSH" >> "$metadata_file"
    else
        echo "- **Sync Method**: Local copy" >> "$metadata_file"
    fi

    echo "- **Timestamp**: $(date +%Y%m%d_%H%M%S)" >> "$metadata_file"

    cat >> "$metadata_file" << EOF

## Notes
- This backup was created automatically by [burrow](https://github.com/this-oliver/burrow)
- Source directory: $original_path
- Absolute source path: $absolute_path
- Backup name: $name
EOF

    if [[ "$backup_type" == "Remote" ]]; then
        echo "- Remote server: $remote_info" >> "$metadata_file"
    fi
}

# 6. Backup local directory
backup_local_directory() {
    local name="$1"
    local original_path="$2"     # Original path from config
    local absolute_path="$3"      # Resolved absolute path
    local backup_num="$4"

    # Verify directory exists
    if [[ ! -d "$absolute_path" ]]; then
        local result="✗ Backup $backup_num: Directory '$original_path' ('$absolute_path') does not exist"
        BACKUP_RESULTS+=("$result")
        echo -e "${RED}$result${NC}"
        ((FAILED_BACKUPS++))
        return 1
    fi

    # Generate filename using name field
    local timestamp zip_name zip_filename
    timestamp=$(date +%Y%m%d_%H%M%S)
    zip_name="${name}_${timestamp}"
    zip_filename="${zip_name}.zip"

    # Create temporary directory for metadata
    local temp_dir
    temp_dir=$(mktemp -d)

    # Copy source directory to temp location
    local temp_source="$temp_dir/$(basename "$absolute_path")"
    cp -r "$absolute_path" "$temp_source"

    # Generate backup metadata
    echo "  Generating backup metadata..."
    generate_backup_metadata "$name" "$original_path" "$absolute_path" "Local" "" "Local copy" "$zip_filename" "$temp_source"

    # Change to temp directory to create zip
    local current_dir
    current_dir=$(pwd)
    cd "$temp_dir"

    # Rename directory being zipped to the name of the backup
    mv "$(basename "$absolute_path")" "$zip_name"

    # Create zip file
    if zip -rq "$current_dir/$zip_filename" "$zip_name"; then
        local result="✓ Backup $backup_num: $name ('$original_path') → $zip_filename"
        BACKUP_RESULTS+=("$result")
        echo -e "${GREEN}$result${NC}"
        ((SUCCESSFUL_BACKUPS++))

        # Change back to original directory and cleanup temp
        cd "$current_dir"
        rm -rf "$temp_dir"
        return 0
    else
        local result="✗ Backup $backup_num: Failed to create zip for '$name' ('$original_path')"
        BACKUP_RESULTS+=("$result")
        echo -e "${RED}$result${NC}"

        # Change back to original directory and cleanup temp
        cd "$current_dir"
        rm -rf "$temp_dir"
        ((FAILED_BACKUPS++))
        return 1
    fi
}

# 7. Backup remote directory
backup_remote_directory() {
    local name="$1"
    local original_path="$2"     # Original path from config
    local absolute_path="$3"      # Resolved absolute path
    local remote_ip="$4"
    local username="$5"
    local port="$6"
    local absolute_key="$7"        # Resolved absolute key path
    local backup_num="$8"

    # Validate SSH key if provided
    local auth_method="Default SSH keys"
    if [[ -n "$absolute_key" && "$absolute_key" != "null" ]]; then
        if [[ ! -f "$absolute_key" ]]; then
            local result="✗ Backup $backup_num: SSH key file '$(basename "$absolute_key")' ('$absolute_key') not found"
            BACKUP_RESULTS+=("$result")
            echo -e "${RED}$result${NC}"
            ((FAILED_BACKUPS++))
            return 1
        fi

        # Check SSH key permissions
        local key_perms
        key_perms=$(stat -f "%Lp" "$absolute_key" 2>/dev/null || stat -c "%a" "$absolute_key" 2>/dev/null)
        if [[ "$key_perms" != "600" && "$key_perms" != "400" ]]; then
            echo -e "${YELLOW}Warning: SSH key '$(basename "$absolute_key")' ('$absolute_key') has insecure permissions ($key_perms). Recommended: 600${NC}"
        fi

        auth_method="SSH key ($absolute_key)"
    fi

    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    local local_path="$temp_dir/$(basename "$absolute_path")"

    # Build rsync command
    local rsync_cmd="rsync -az -e 'ssh -p $port"
    if [[ -n "$absolute_key" && "$absolute_key" != "null" ]]; then
        rsync_cmd+=" -i $absolute_key"
    fi
    if [[ -n "$username" && "$username" != "null" ]]; then
        rsync_cmd+=" -l $username"
    fi
    rsync_cmd+="'"

    # Add source path
    if [[ -n "$username" && "$username" != "null" ]]; then
        rsync_cmd+=" $username@$remote_ip:$original_path"
    else
        rsync_cmd+=" $remote_ip:$original_path"
    fi

    rsync_cmd+=" $local_path"

    # Execute rsync
    echo "  Syncing remote directory to local temporary location..."
    if ! eval "$rsync_cmd"; then
        local result="✗ Backup $backup_num: Failed to sync remote directory '$original_path' ('$absolute_path') from $remote_ip"
        BACKUP_RESULTS+=("$result")
        echo -e "${RED}$result${NC}"
        rm -rf "$temp_dir"
        ((FAILED_BACKUPS++))
        return 1
    fi

    # Verify synced directory exists
    if [[ ! -d "$local_path" ]]; then
        local result="✗ Backup $backup_num: Remote directory '$original_path' ('$absolute_path') not found on server"
        BACKUP_RESULTS+=("$result")
        echo -e "${RED}$result${NC}"
        rm -rf "$temp_dir"
        ((FAILED_BACKUPS++))
        return 1
    fi

    # Generate filename using name field
    local timestamp zip_name zip_filename
    timestamp=$(date +%Y%m%d_%H%M%S)
    zip_name="${name}_${timestamp}"
    zip_filename="${zip_name}.zip"

    # Generate backup metadata
    echo "  Generating backup metadata..."
    generate_backup_metadata "$name" "$original_path" "$absolute_path" "Remote" "$remote_ip" "$auth_method" "$zip_filename" "$local_path"

    # Change to temp directory to create zip
    current_dir=$(pwd)
    cd $temp_dir

    # Rename directory being zipped to the name of the backup
    mv "$(basename "$absolute_path")" "$zip_name"

    # Create zip file
    if zip -rq "$current_dir/$zip_filename" "$zip_name"; then
        local result="✓ Backup $backup_num: $name ('$original_path' from $remote_ip) -> $zip_filename"
        BACKUP_RESULTS+=("$result")
        echo -e "${GREEN}$result${NC}"
        ((SUCCESSFUL_BACKUPS++))
    else
        local result="✗ Backup $backup_num: Failed to create zip for remote directory '$name' ('$original_path')"
        BACKUP_RESULTS+=("$result")
        echo -e "${RED}$result${NC}"
        ((FAILED_BACKUPS++))
    fi

    # Cleanup temporary directory
    cd $current_dir
    rm -rf "$temp_dir"
}

# 8. Print summary report
print_summary() {
    echo
    echo -e "${YELLOW}=== Backup Summary ===${NC}"

    for result in "${BACKUP_RESULTS[@]}"; do
        if [[ "$result" =~ ^✓ ]]; then
            echo -e "${GREEN}$result${NC}"
        else
            echo -e "${RED}$result${NC}"
        fi
    done

    echo
    echo -e "${YELLOW}Total: $TOTAL_BACKUPS backups, $SUCCESSFUL_BACKUPS successful, $FAILED_BACKUPS failed${NC}"

    if [[ $FAILED_BACKUPS -eq 0 ]]; then
        echo -e "${GREEN}All backups completed successfully!${NC}"
        exit 0
    else
        echo -e "${RED}Some backups failed. Check the results above.${NC}"
        exit 1
    fi
}

# 9. Main execution
main() {
    echo "Starting backup process..."
    echo

    # Check dependencies
    check_dependencies

    # Parse arguments
    parse_arguments "$@"

    # Load configuration
    load_config

    echo

    # Process all backups
    for ((i=0; i<TOTAL_BACKUPS; i++)); do
        process_backup "$i" || true
        echo
    done

    # Print summary
    print_summary
}

# Execute main function with all arguments
main "$@"
