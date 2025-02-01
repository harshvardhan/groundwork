#!/bin/bash

# Check if directory path is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <module_directory_path>"
    exit 1
fi

MODULE_DIR=$1

# Extract module name from path (last directory in path)
MODULE_NAME=$(basename "$MODULE_DIR")

# Get current timestamp in format YYYYMMDD_HHMMSS
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# Create output filename using module name and timestamp
OUTPUT_FILE="${MODULE_NAME}_${TIMESTAMP}.txt"

# Check if directory exists
if [ ! -d "$MODULE_DIR" ]; then
    echo "Error: Directory $MODULE_DIR does not exist"
    exit 1
fi

# Remove output file if it exists
rm -f "$OUTPUT_FILE"

# Add module info header
echo "=== Module: $MODULE_NAME ===" > "$OUTPUT_FILE"
echo "=== Generated: $(date) ===" >> "$OUTPUT_FILE"
echo "=== Path: $MODULE_DIR ===" >> "$OUTPUT_FILE"
echo -e "\n" >> "$OUTPUT_FILE"

# Find build.gradle and text files under src
find "$MODULE_DIR" \( -name "build.gradle" -o -path "*/src/*" \) \
    -type f \
    \( -name "*.kt" -o -name "*.java" -o -name "*.xml" -o -name "*.gradle" \
       -o -name "*.properties" -o -name "*.txt" -o -name "*.md" -o -name "*.js" \) \
    -not -path "*/\.*" \
    -not -path "*/build/*" \
    -not -path "*/generated/*" \
    -not -path "*/intermediates/*" \
    | sort \
    | while read -r file; do
    
    # Get relative path
    relative_path=${file#$MODULE_DIR/}
    
    # Add file header
    echo -e "\n\n=== File: $relative_path ===" >> "$OUTPUT_FILE"
    echo -e "=== Path: $file ===" >> "$OUTPUT_FILE"
    echo -e "=== Content ===\n" >> "$OUTPUT_FILE"
    
    # Add file content
    cat "$file" >> "$OUTPUT_FILE"
done

echo "Created $OUTPUT_FILE containing text files from build.gradle and src"
echo "Total files processed: $(grep -c "=== File:" "$OUTPUT_FILE")"
