#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

#######################################
# Configuration
#######################################
readonly MAX_FILE_SIZE=$((1024 * 1024))  # 1MB
readonly MAX_MEMORY_KB=$((1024 * 1024))  # 1GB
readonly FILE_PROCESS_TIMEOUT=30  # seconds
readonly EXCLUDE_PATTERNS=(
    '*/build/*'
    '*/test/*'
    '*/androidTest/*'
    '*/generated/*'
)

#######################################
# Platform-specific functions
#######################################
get_relative_path() {
    local target="$1"
    local base="$2"
    
    # Remove trailing slash from base path
    base="${base%/}"
    
    # Remove base path and leading slash from target path
    echo "${target#$base/}"
}

#######################################
# Print usage information and exit
#######################################
print_usage() {
    echo "Usage: $0 <project_root> <entry_file> [max_depth]"
    echo "  project_root: Root directory of the Android project"
    echo "  entry_file  : Starting file to analyze dependencies"
    echo "  max_depth   : Optional maximum depth (default: unlimited)"
    exit 1
}

#######################################
# Validate positional parameters
#######################################
if [ "$#" -lt 2 ]; then
    print_usage
fi

PROJECT_ROOT=$(cd "$1" && pwd)
ENTRY_FILE=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
MAX_DEPTH=${3:-"-1"}  # -1 means unlimited

if [ ! -d "$PROJECT_ROOT" ]; then
    echo "Error: Project root '$PROJECT_ROOT' is not a directory."
    exit 1
fi

if [ ! -f "$ENTRY_FILE" ]; then
    echo "Error: Entry file '$ENTRY_FILE' does not exist."
    exit 1
fi

#######################################
# Set up output directories and log file
#######################################
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
OUTPUT_DIR="dependency_analysis_${TIMESTAMP}"
PROCESSED_FILES_DIR="$OUTPUT_DIR/processed_files"
TEMP_DIR="$OUTPUT_DIR/temp"
LOG_DIR="$OUTPUT_DIR/logs"
LOG_FILE="$LOG_DIR/analysis.log"

mkdir -p "$PROCESSED_FILES_DIR" "$TEMP_DIR" "$LOG_DIR"

#######################################
# Logging function
#######################################
log() {
    local level="$1"
    shift
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    echo "$message" >> "$LOG_FILE"
    echo "$message"
}

#######################################
# Resource check functions
#######################################
check_memory() {
    local mem_used
    mem_used=$(ps -o rss= -p $$ | awk '{print $1}')
    
    if [ "${mem_used:-0}" -gt "$MAX_MEMORY_KB" ]; then
        log "WARN" "High memory usage detected: $((mem_used/1024))MB"
        return 1
    fi
    return 0
}

check_file_size() {
    local file="$1"
    local size
    size=$(stat -f%z "$file")
    
    if [ "$size" -gt "$MAX_FILE_SIZE" ]; then
        log "WARN" "Skipping large file: $file ($((size/1024))KB)"
        return 1
    fi
    return 0
}

should_exclude() {
    local file="$1"
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        if [[ "$file" =~ $pattern ]]; then
            log "DEBUG" "File excluded by pattern ($pattern): $file"
            return 0
        fi
    done
    return 1
}

#######################################
# Filter project-specific imports
# Ignores standard libraries and only processes project imports
#######################################
is_project_import() {
    local import_stmt="$1"
    local project_package="sg.com.sph"  # Your project's base package
    
    # Skip common non-project imports
    [[ "$import_stmt" =~ ^import\ android\. ]] && return 1
    [[ "$import_stmt" =~ ^import\ java\. ]] && return 1
    [[ "$import_stmt" =~ ^import\ javax\. ]] && return 1
    [[ "$import_stmt" =~ ^import\ kotlin\. ]] && return 1
    [[ "$import_stmt" =~ ^import\ androidx\. ]] && return 1
    [[ "$import_stmt" =~ ^import\ com\.google\. ]] && return 1
    [[ "$import_stmt" =~ ^import\ org\.json\. ]] && return 1
    
    # Check if it's a project import
    [[ "$import_stmt" =~ ^import\ $project_package\. ]] && return 0
    
    return 1
}

#######################################
# Find file from import statement
#######################################
find_file_from_import() {
    local import_stmt="$1"
    local project_root="$2"
    
    # Skip if not a project import
    if ! is_project_import "$import_stmt"; then
        log "DEBUG" "Skipping non-project import: $import_stmt"
        return
    fi
    
    log "DEBUG" "Processing project import: $import_stmt"
    
    # Extract the full class path without 'import' keyword, semicolon and 'as' alias
    local full_import
    full_import=$(echo "$import_stmt" | sed -e 's/^import[[:space:]]\+//' -e 's/[[:space:]]\+as[[:space:]]\+.\+$//' -e 's/;$//')
    
    # Get the class name for fallback search
    local class_name
    class_name=$(basename "$full_import")
    
    log "DEBUG" "Looking for class: $class_name in package: $full_import"
    
    # Use more efficient find with pruning
    local found_file
    found_file=$(find "$project_root" -type d \( -name "build" -o -name "test" -o -name "androidTest" -o -name "generated" \) -prune -o \
        -path "*/src/main/java/*" -type f \( -name "${class_name}.kt" -o -name "${class_name}.java" \) -print | \
        while read -r file; do
            # Check if the file path contains the package structure
            if [[ "$file" =~ .*/${full_import//./\/}\.(kt|java)$ ]]; then
                echo "$file"
                break
            fi
        done)
    
    if [ -n "$found_file" ]; then
        log "DEBUG" "Found file: $found_file"
        echo "$found_file"
    else
        log "DEBUG" "Could not find file for import: $full_import"
    fi
}

#######################################
# Cache implementation using file-based approach
#######################################
CACHE_DIR="$TEMP_DIR/cache"
mkdir -p "$CACHE_DIR"

is_cached() {
    local file="$1"
    local cache_key
    cache_key=$(echo "$file" | md5sum | cut -d' ' -f1)
    [ -f "$CACHE_DIR/$cache_key" ]
}

add_to_cache() {
    local file="$1"
    local cache_key
    cache_key=$(echo "$file" | md5sum | cut -d' ' -f1)
    touch "$CACHE_DIR/$cache_key"
}

#######################################
# Process file
#######################################
process_file() {
    local file="$1"
    local depth="$2"

    # Use cache to avoid reprocessing
    if is_cached "$file"; then
        log "DEBUG" "File already processed (cached): $file"
        return
    fi
    add_to_cache "$file"

    log "DEBUG" "Starting to process file: $file at depth $depth"

    # Check max depth
    if [ "$MAX_DEPTH" -ge 0 ] && [ "$depth" -gt "$MAX_DEPTH" ]; then
        log "DEBUG" "Maximum depth reached for: $file"
        return
    fi

    # Get relative path and create output file path
    local relative_path
    relative_path=$(get_relative_path "$file" "$PROJECT_ROOT")
    local output_file
    output_file="${PROCESSED_FILES_DIR}/$(echo "$relative_path" | tr '/' '_')"

    # Skip if already processed
    if [ -f "$output_file" ]; then
        log "DEBUG" "File already processed: $relative_path"
        return
    fi

    # Resource checks
    if ! check_memory || ! check_file_size "$file" || should_exclude "$file"; then
        return
    fi  # Changed this line - removed the extra }

    # Create file content
    {
        echo "=== File: $relative_path ==="
        echo "=== Depth: $depth ==="
        echo "=== Processed: $(date) ==="
        echo "=== Content ==="
        echo
        if [[ "$file" =~ \.(kt|java)$ ]]; then
            log "DEBUG" "Filtering imports from Kotlin/Java file"
            grep -v '^[[:space:]]*import ' "$file"
        else
            log "DEBUG" "Copying entire file content"
            cat "$file"
        fi
    } > "$output_file"


    # Process dependencies based on file type
    case "$file" in
        *.kt|*.java)
            log "DEBUG" "Analyzing Java/Kotlin file: $relative_path"
            while IFS= read -r line; do
                if [[ $line =~ ^import\  ]]; then
                    if is_project_import "$line"; then
                        log "DEBUG" "Found project import: $line"
                        local dep_file
                        dep_file=$(find_file_from_import "$line" "$PROJECT_ROOT")
                        if [ -n "$dep_file" ]; then
                            log "DEBUG" "Found dependency: $dep_file"
                            process_file "$dep_file" $((depth + 1))
                        fi
                    else
                        log "DEBUG" "Skipping non-project import: $line"
                    fi
                fi
            done < "$file"
            ;;
        *.xml)
            log "DEBUG" "Analyzing XML file: $relative_path"
            grep -o 'layout="@layout/[^"]\+"' "$file" | cut -d'"' -f2 | cut -d'/' -f2 | while read -r layout; do
                local layout_file
                layout_file=$(find "$PROJECT_ROOT" -type f -name "${layout}.xml" | grep -v "/build/" | head -n 1)
                if [ -n "$layout_file" ]; then
                    process_file "$layout_file" $((depth + 1))
                fi
            done
            
            grep -o 'class="[^"]\+"' "$file" | cut -d'"' -f2 | while read -r class_name; do
                if [[ "$class_name" =~ ^sg\.com\.sph\. ]]; then
                    local class_file
                    class_file=$(find "$PROJECT_ROOT" -path "*/src/main/java/*" -type f \( -name "$(basename "$class_name").kt" -o -name "$(basename "$class_name").java" \) | grep -v "/build/" | head -n 1)
                    if [ -n "$class_file" ]; then
                        process_file "$class_file" $((depth + 1))
                    fi
                fi
            done
            ;;
        *.gradle)
            log "DEBUG" "Analyzing Gradle file: $relative_path"
            # ... (gradle processing remains the same) ...
            ;;
    esac
}


#######################################
# Main execution
#######################################
log "INFO" "Starting analysis with:"
log "INFO" "Project root: $PROJECT_ROOT"
log "INFO" "Entry file: $ENTRY_FILE"
log "INFO" "Max depth: $MAX_DEPTH"
log "INFO" "Output directory: $OUTPUT_DIR"

# Count total files
total_files=$(find "$PROJECT_ROOT" -type f \( -name "*.kt" -o -name "*.java" -o -name "*.xml" -o -name "*.gradle" \) -not -path '*/\.*' | wc -l)
log "INFO" "Total files found in project: $total_files"

# Start analysis
log "INFO" "Starting main file processing"
process_file "$ENTRY_FILE" 0

# Create summary and combined files
SUMMARY_FILE="$OUTPUT_DIR/analysis_summary.txt"
{
    echo "=== Dependency Analysis Summary ==="
    echo "Generated    : $(date)"
    echo "Project Root : $PROJECT_ROOT"
    echo "Entry File   : $ENTRY_FILE"
    echo "Max Depth    : $MAX_DEPTH"
    echo
    echo "=== Processed Files ==="
    find "$PROCESSED_FILES_DIR" -type f -exec basename {} \; | sort
} > "$SUMMARY_FILE"

COMBINED_FILE="$OUTPUT_DIR/combined_analysis.txt"
{
    cat "$SUMMARY_FILE"
    echo
    echo "=== Detailed Analysis ==="
    find "$PROCESSED_FILES_DIR" -type f -exec cat {} \;
} > "$COMBINED_FILE"

log "INFO" "Analysis complete!"
log "INFO" "Files generated:"
log "INFO" "  Combined analysis: $COMBINED_FILE"
log "INFO" "  Summary         : $SUMMARY_FILE"
log "INFO" "  Logs           : $LOG_FILE"
log "INFO" "  Processed files : $PROCESSED_FILES_DIR"

# Show directory contents
log "INFO" "Output directory contents:"
ls -la "$OUTPUT_DIR" | while read -r line; do
    log "INFO" "  $line"
done