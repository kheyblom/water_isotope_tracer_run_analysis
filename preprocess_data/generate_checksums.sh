#!/bin/bash

# Script to generate MD5 checksums, skipping files that have already been processed
# Usage: ./generate_checksums.sh [num_parallel_jobs]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKSUMS_FILE="${SCRIPT_DIR}/checksums.md5"
ERRORS_FILE="${SCRIPT_DIR}/checksums_errors.log"
TEMP_DIR="${SCRIPT_DIR}/.checksum_temp"
PARALLEL_JOBS="${1:-8}"

# Create temp directory for processing
mkdir -p "${TEMP_DIR}"

# Function to extract already processed files
get_processed_files() {
    if [[ -f "${CHECKSUMS_FILE}" ]]; then
        # Extract file paths from checksums.md5 (second column)
        awk '{print $2}' "${CHECKSUMS_FILE}" | sort > "${TEMP_DIR}/processed_files.txt"
        echo "Found $(wc -l < "${TEMP_DIR}/processed_files.txt") already processed files"
    else
        touch "${TEMP_DIR}/processed_files.txt"
        echo "No existing checksums file found, starting fresh"
    fi
}

# Function to find files that need processing
find_unprocessed_files() {
    echo "Finding all files..."
    # Find all files and sort them
    find "${SCRIPT_DIR}" -type f ! -name "checksums.md5" ! -name "checksums_errors.log" ! -name "generate_checksums.sh" ! -path "${TEMP_DIR}/*" | sort > "${TEMP_DIR}/all_files.txt"
    
    # Use comm to find files not in processed list (more efficient than grep for each file)
    comm -23 "${TEMP_DIR}/all_files.txt" "${TEMP_DIR}/processed_files.txt" | tr '\n' '\0' > "${TEMP_DIR}/unprocessed_files.txt"
    
    local count=$(tr '\0' '\n' < "${TEMP_DIR}/unprocessed_files.txt" | wc -l)
    echo "Found ${count} files to process"
    
    if [[ ${count} -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Function to process files
process_files() {
    if [[ ! -s "${TEMP_DIR}/unprocessed_files.txt" ]]; then
        echo "No files to process!"
        return 0
    fi
    
    echo "Starting MD5 checksum generation with ${PARALLEL_JOBS} parallel jobs..."
    echo "Output will be appended to ${CHECKSUMS_FILE}"
    echo "Errors will be logged to ${ERRORS_FILE}"
    
    # Process files in parallel and append to checksums file
    cat "${TEMP_DIR}/unprocessed_files.txt" | \
        xargs -0 -P "${PARALLEL_JOBS}" -n 1 md5sum >> "${CHECKSUMS_FILE}" 2>> "${ERRORS_FILE}"
    
    local exit_code=$?
    if [[ ${exit_code} -eq 0 ]]; then
        echo "Successfully processed all files!"
    else
        echo "Some errors occurred. Check ${ERRORS_FILE} for details."
    fi
    
    return ${exit_code}
}

# Cleanup function
cleanup() {
    rm -rf "${TEMP_DIR}"
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Main execution
main() {
    echo "=== MD5 Checksum Generator (Resumable) ==="
    echo "Working directory: ${SCRIPT_DIR}"
    echo "Parallel jobs: ${PARALLEL_JOBS}"
    echo ""
    
    get_processed_files
    find_unprocessed_files
    
    if [[ $? -eq 0 ]]; then
        echo "All files have already been processed!"
        exit 0
    fi
    
    process_files
    exit $?
}

# Run main function
main
