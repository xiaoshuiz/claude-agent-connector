#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-"${ROOT_DIR}/dist"}"
APP_NAME="ClaudeAgentConnector"
SCHEME="${APP_NAME}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_DIR="${ROOT_DIR}/.build/DerivedData"
PROJECT_FILE="${ROOT_DIR}/${APP_NAME}.xcodeproj"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen 未安装，请先执行: brew install xcodegen"
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild 未找到，请在 macOS + Xcode 环境中执行。"
  exit 1
fi

echo "==> 生成 Xcode 工程"
xcodegen generate --spec "${ROOT_DIR}/project.yml"

echo "==> 开始构建 ${SCHEME} (${CONFIGURATION})"
xcodebuild \
  -project "${PROJECT_FILE}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "platform=macOS" \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  clean build \
  CODE_SIGNING_ALLOWED=NO

APP_PATH="${DERIVED_DATA_DIR}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
if [[ ! -d "${APP_PATH}" ]]; then
  echo "构建完成但未找到产物: ${APP_PATH}"
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"
ZIP_NAME="${APP_NAME}-macOS-${CONFIGURATION}.zip"
ZIP_PATH="${OUTPUT_DIR}/${ZIP_NAME}"

echo "==> 打包 ${ZIP_PATH}"
ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"
shasum -a 256 "${ZIP_PATH}" > "${ZIP_PATH}.sha256"

echo "==> 完成"
echo "App: ${APP_PATH}"
echo "Zip: ${ZIP_PATH}"
echo "SHA256: ${ZIP_PATH}.sha256"
