#!/bin/bash
set -euo pipefail

# RLENV Build Script
# This script rebuilds the application from source located at /rlenv/source/minimp4/
#
# Original image: ghcr.io/mayhemheroes/minimp4:master
# Git revision: 563e2818bc0d811678b2f56313d1ebc295cf3a4e

# ============================================================================
# REQUIRED: Change to Source Directory
# ============================================================================
cd /rlenv/source/minimp4

# ============================================================================
# Clean Previous Build (recommended)
# ============================================================================
# Clean local build artifact
rm -f minimp4_x86

# Try to remove the target executable (may fail due to permissions, that's OK)
rm -f /minimp4_x86 2>/dev/null || true

# ============================================================================
# Build Commands (NO NETWORK, NO PACKAGE INSTALLATION)
# ============================================================================
# Build the minimp4_x86 target with optimizations and flags
gcc -flto -O3 -std=gnu11 -DNDEBUG -D_FILE_OFFSET_BITS=64 \
    -fno-stack-protector -ffunction-sections -fdata-sections -Wl,--gc-sections \
    -o minimp4_x86 minimp4_test.c -lm -lpthread

# ============================================================================
# Copy Artifacts (use 'cat >' for busybox compatibility)
# ============================================================================
# Use 'cat >' instead of 'cp' for busybox compatibility
cat minimp4_x86 > /minimp4_x86

# ============================================================================
# Set Permissions
# ============================================================================
chmod 777 /minimp4_x86 2>/dev/null || true

# ============================================================================
# REQUIRED: Verify Build Succeeded
# ============================================================================
if [ ! -f /minimp4_x86 ]; then
    echo "Error: Build artifact not found at /minimp4_x86"
    exit 1
fi

# Verify executable bit
if [ ! -x /minimp4_x86 ]; then
    echo "Warning: Build artifact is not executable"
fi

# Verify file size (basic sanity check)
SIZE=$(stat -c%s /minimp4_x86 2>/dev/null || stat -f%z /minimp4_x86 2>/dev/null || echo 0)
if [ "$SIZE" -lt 1000 ]; then
    echo "Warning: Build artifact is suspiciously small ($SIZE bytes)"
fi

echo "Build completed successfully: /minimp4_x86 ($SIZE bytes)"
