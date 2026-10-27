#!/bin/sh
set -eu

package_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_model="$package_dir/Tests/CoreDataMappingTests/MedicalCongress/Resources/MedicalCongressModel.xcdatamodeld"
compiled_model="$package_dir/Tests/CoreDataMappingTests/MedicalCongress/Resources/MedicalCongressModel.momd"
sdkroot=$(xcrun --sdk macosx --show-sdk-path)

xcrun momc \
  --sdkroot "$sdkroot" \
  --macosx-deployment-target 15.0 \
  "$source_model" "$compiled_model"
