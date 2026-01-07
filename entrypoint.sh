#!/usr/bin/env bash
# usage: ./zip_dir.sh /path/to/dir
# Zips the given directory into the current working directory.

set -euo pipefail

# 1. Ensure an argument was supplied
if [[ $# -ne 1 ]]; then
    echo "Error: Directory path required."
    echo "Usage: $0 <directory_path>"
    exit 1
fi

DIR="$1"

# 2. Verify that the path exists and is a directory
if [[ ! -d "$DIR" ]]; then
    echo "Error: '$DIR' is not a directory or does not exist."
    exit 1
fi

# 3. Determine the zip file name
# Current date/time for the file name (YYYYMMDD_HHMMSS)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
# e.g. /foo/bar → bar_20240612_153045.zip
ZIP_NAME="$(basename "$DIR")_${TIMESTAMP}.zip"

# 4. Create the zip in the current working directory
#    -r: recurse into subdirectories
#    -q: quiet output (optional)
zip -rq "$ZIP_NAME" "$DIR"

echo "Created '$ZIP_NAME' in $(pwd)."
