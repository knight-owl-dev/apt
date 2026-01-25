#!/usr/bin/env bash
# Cross-platform checksum and file size functions

# Get file size in bytes
# Usage: get_file_size "/path/to/file"
get_file_size() {
    local file="$1"
    local result
    if result=$(stat -c %s "$file" 2>/dev/null) && [[ "$result" =~ ^[0-9]+$ ]]; then
        echo "$result"
    elif result=$(stat -f %z "$file" 2>/dev/null) && [[ "$result" =~ ^[0-9]+$ ]]; then
        echo "$result"
    else
        return 1
    fi
}

# Get MD5 checksum
# Usage: get_md5 "/path/to/file"
get_md5() {
    local file="$1"
    local result
    if result=$(md5sum "$file" 2>/dev/null | cut -d' ' -f1) && [[ -n "$result" ]]; then
        echo "$result"
    elif result=$(md5 -q "$file" 2>/dev/null); then
        echo "$result"
    else
        return 1
    fi
}

# Get SHA1 checksum
# Usage: get_sha1 "/path/to/file"
get_sha1() {
    local file="$1"
    local result
    if result=$(sha1sum "$file" 2>/dev/null | cut -d' ' -f1) && [[ -n "$result" ]]; then
        echo "$result"
    elif result=$(shasum -a 1 "$file" 2>/dev/null | cut -d' ' -f1); then
        echo "$result"
    else
        return 1
    fi
}

# Get SHA256 checksum
# Usage: get_sha256 "/path/to/file"
get_sha256() {
    local file="$1"
    local result
    if result=$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1) && [[ -n "$result" ]]; then
        echo "$result"
    elif result=$(shasum -a 256 "$file" 2>/dev/null | cut -d' ' -f1); then
        echo "$result"
    else
        return 1
    fi
}
