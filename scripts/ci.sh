#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
{
  sw_vers
  xcodebuild -version
  swift --version
  git rev-parse HEAD
} | tee build/environment.txt
swift package describe
swift build
# The bootstrap has no behavior to unit-test. Once Core exists, missing tests fail CI.
if [ -d Sources/OverSlayCore ] || [ -d Tests ]; then
  swift test --parallel 2>&1 | tee build/tests.txt
else
  echo 'NOT RUN: bootstrap only; add Core and behavioral tests in implementation step 1.' | tee build/tests.txt
fi
bash scripts/package-app.sh
