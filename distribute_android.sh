#!/bin/bash
set -euo pipefail

echo "Running Android release validation..."
(cd android && ./gradlew :app:validateGraceReleaseConfig)

echo "Building Android App Bundle..."
flutter build appbundle --release

echo "Build successful! Distributing to Firebase..."
firebase appdistribution:distribute build/app/outputs/bundle/release/app-release.aab \
  --app 1:47100126669:android:a6100cb15fd1a070a65084 \
  --groups "testers"
