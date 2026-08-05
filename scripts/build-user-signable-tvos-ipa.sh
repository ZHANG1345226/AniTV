#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT_PATH="${PROJECT_PATH:-${PROJECT_ROOT}/AniTV.xcodeproj}"
SCHEME="${SCHEME:-AniTV}"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="${APP_NAME:-AniTV}"
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/scripts/output/user-signable-ipa}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${PROJECT_ROOT}/scripts/output/derived-data-user-signable}"

SECRETS_PLIST_PATH="${SECRETS_PLIST_PATH:-}"

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}-appletvos/${APP_NAME}.app"
PAYLOAD_DIR="${OUTPUT_DIR}/Payload"
IPA_PATH="${OUTPUT_DIR}/${APP_NAME}-${CONFIGURATION}-user-signable-tvos.ipa"

echo "==> Generating obfuscated secrets code"
SRCROOT="${PROJECT_ROOT}" SECRETS_PLIST_PATH="${SECRETS_PLIST_PATH}" python3 "${SCRIPT_DIR}/generate_secrets.py"

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
