#!/usr/bin/env bash

set -euo pipefail

PROJECT_PATH="${PROJECT_PATH:-AniTV.xcodeproj}"
SCHEME="${SCHEME:-AniTV}"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="${APP_NAME:-AniTV}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/scripts/output/user-signable-ipa}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$(pwd)/scripts/output/derived-data-user-signable}"

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}-appletvos/${APP_NAME}.app"
PAYLOAD_DIR="${OUTPUT_DIR}/Payload"
IPA_PATH="${OUTPUT_DIR}/${APP_NAME}-${CONFIGURATION}-user-signable-tvos.ipa"

echo "==> Cleaning output directory"
rm -rf "${OUTPUT_DIR}"
mkdir -p "${PAYLOAD_DIR}"

echo "==> Building tvOS app without code signing"
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination 'generic/platform=tvOS' \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  AD_HOC_CODE_SIGNING_ALLOWED=NO

if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: built app not found at ${APP_PATH}" >&2
  exit 1
fi

echo "==> Packaging unsigned app into ipa"
cp -R "${APP_PATH}" "${PAYLOAD_DIR}/"
(
  cd "${OUTPUT_DIR}"
  ditto -c -k --sequesterRsrc --keepParent Payload "${IPA_PATH}"
)

echo "==> Done"
echo "IPA: ${IPA_PATH}"
echo "Note: this IPA is not signed. Users still need to re-sign it with their own certificate/profile before installing."
