#!/bin/bash

################################################################################
# RoomPlan App - Archive Build Script
################################################################################
#
# This script builds an xcarchive for the RoomPlan app, ready for:
# - App Store submission
# - TestFlight distribution
# - Ad-hoc distribution
#
# The archive is placed in the /build directory (which is git-ignored)
#
# Usage:
#   ./scripts/build_archive.sh [configuration]
#
# Parameters:
#   configuration - Optional. Either 'Debug' or 'Release' (default: Release)
#
# Examples:
#   ./scripts/build_archive.sh              # Build Release archive
#   ./scripts/build_archive.sh Debug        # Build Debug archive
#   ./scripts/build_archive.sh Release      # Build Release archive
#
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONFIGURATION="${1:-Release}"
SCHEME="RoomPlanSimple"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/RoomPlanSimple.xcarchive"
DATE_STAMP=$(date +"%Y%m%d_%H%M%S")
ARCHIVE_PATH_DATED="${BUILD_DIR}/RoomPlanSimple_${DATE_STAMP}.xcarchive"

echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  RoomPlan App - Archive Build Script${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}Configuration:${NC} ${CONFIGURATION}"
echo -e "${GREEN}Scheme:${NC} ${SCHEME}"
echo -e "${GREEN}Project Directory:${NC} ${PROJECT_DIR}"
echo -e "${GREEN}Build Directory:${NC} ${BUILD_DIR}"
echo ""

# Validate configuration
if [[ "${CONFIGURATION}" != "Debug" && "${CONFIGURATION}" != "Release" ]]; then
    echo -e "${RED}Error: Configuration must be 'Debug' or 'Release'${NC}"
    echo "Usage: $0 [Debug|Release]"
    exit 1
fi

# Create build directory if it doesn't exist
if [ ! -d "${BUILD_DIR}" ]; then
    echo -e "${YELLOW}Creating build directory...${NC}"
    mkdir -p "${BUILD_DIR}"
fi

# Clean previous archives (optional - keep last 5)
echo -e "${YELLOW}Cleaning old archives (keeping last 5)...${NC}"
cd "${BUILD_DIR}"
ls -t RoomPlanSimple*.xcarchive 2>/dev/null | tail -n +6 | xargs -I {} rm -rf {} 2>/dev/null || true
cd "${PROJECT_DIR}"

# Clean build folder
echo -e "${YELLOW}Cleaning build folder...${NC}"
xcodebuild clean \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -quiet

# Build archive
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Building Archive...${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo ""

xcodebuild archive \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -archivePath "${ARCHIVE_PATH_DATED}" \
    -destination "generic/platform=iOS" \
    -allowProvisioningUpdates \
    | xcbeautify 2>/dev/null || xcodebuild archive \
        -scheme "${SCHEME}" \
        -configuration "${CONFIGURATION}" \
        -archivePath "${ARCHIVE_PATH_DATED}" \
        -destination "generic/platform=iOS" \
        -allowProvisioningUpdates

# Check if archive was created successfully
if [ ! -d "${ARCHIVE_PATH_DATED}" ]; then
    echo ""
    echo -e "${RED}════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  Archive Build Failed!${NC}"
    echo -e "${RED}════════════════════════════════════════════════════════${NC}"
    exit 1
fi

# Create/update symlink to latest archive
rm -f "${ARCHIVE_PATH}"
ln -s "$(basename "${ARCHIVE_PATH_DATED}")" "${ARCHIVE_PATH}"

# Get archive info
ARCHIVE_SIZE=$(du -sh "${ARCHIVE_PATH_DATED}" | cut -f1)
APP_PATH="${ARCHIVE_PATH_DATED}/Products/Applications/RoomPlanSimple.app"

# Extract version info if available
if [ -f "${APP_PATH}/Info.plist" ]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PATH}/Info.plist" 2>/dev/null || echo "Unknown")
    BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${APP_PATH}/Info.plist" 2>/dev/null || echo "Unknown")
else
    VERSION="Unknown"
    BUILD="Unknown"
fi

# Success message
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Archive Build Succeeded!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}Archive Information:${NC}"
echo -e "  Location: ${ARCHIVE_PATH_DATED}"
echo -e "  Size: ${ARCHIVE_SIZE}"
echo -e "  Version: ${VERSION}"
echo -e "  Build: ${BUILD}"
echo -e "  Configuration: ${CONFIGURATION}"
echo ""
echo -e "${GREEN}Symlink:${NC} ${ARCHIVE_PATH} → $(basename "${ARCHIVE_PATH_DATED}")"
echo ""

# Next steps
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Next Steps${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}To export IPA for distribution:${NC}"
echo ""
echo -e "  1. Open Xcode Organizer:"
echo -e "     ${BLUE}Xcode → Window → Organizer${NC}"
echo ""
echo -e "  2. Select the archive:"
echo -e "     ${BLUE}${ARCHIVE_PATH_DATED}${NC}"
echo ""
echo -e "  3. Click 'Distribute App' and choose:"
echo -e "     - ${GREEN}App Store Connect${NC} (for TestFlight/App Store)"
echo -e "     - ${GREEN}Ad Hoc${NC} (for testing on registered devices)"
echo -e "     - ${GREEN}Enterprise${NC} (if you have enterprise account)"
echo -e "     - ${GREEN}Development${NC} (for debugging)"
echo ""
echo -e "${YELLOW}Or use command line:${NC}"
echo ""
echo -e "  ${BLUE}./scripts/export_ipa.sh${NC} (if you create this script)"
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo ""

# List all archives
echo -e "${GREEN}Available archives in build directory:${NC}"
ls -lh "${BUILD_DIR}"/*.xcarchive 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}' || echo "  (none)"
echo ""

exit 0
