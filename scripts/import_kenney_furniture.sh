#!/bin/sh
set -eu

SOURCE_URL="https://kenney.nl/media/pages/assets/furniture-kit/440e0608a4-1677580847/kenney_furniture-kit.zip"
EXPECTED_SHA256="e67652d0932cee41683f74711c03d3e192a2af9979ef8e6b237711f5482d46b0"
OUTPUT_DIR="${1:-RoomPlanSimple/FurnitureAssets}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

curl -fL "$SOURCE_URL" -o "$WORK_DIR/furniture-kit.zip"
ACTUAL_SHA256="$(shasum -a 256 "$WORK_DIR/furniture-kit.zip" | awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
    echo "Furniture Kit checksum mismatch: $ACTUAL_SHA256" >&2
    exit 1
fi

unzip -q "$WORK_DIR/furniture-kit.zip" -d "$WORK_DIR/source"
mkdir -p "$OUTPUT_DIR"

copy_model() {
    xcrun scntool \
        --convert "$WORK_DIR/source/Models/DAE format/$1.dae" \
        --format usdz \
        --output "$OUTPUT_DIR/$2.usdz"
}

copy_model bookcaseClosedDoors storage
copy_model kitchenFridge refrigerator
copy_model kitchenStove stove
copy_model bedDouble bed
copy_model bathroomSink sink
copy_model washerDryerStacked washerDryer
copy_model toilet toilet
copy_model bathtub bathtub
copy_model kitchenStoveElectric oven
copy_model kitchenCabinet dishwasher
copy_model table table
copy_model loungeSofa sofa
copy_model chair chair
copy_model kitchenStove fireplace
copy_model televisionModern television
copy_model stairs stairs
cp "$WORK_DIR/source/License.txt" "$OUTPUT_DIR/KENNEY_LICENSE.txt"

echo "Imported verified Kenney Furniture Kit assets into $OUTPUT_DIR"
