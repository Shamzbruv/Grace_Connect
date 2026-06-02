#!/bin/bash

echo "Building iOS IPA..."
flutter build ipa --release

if [ $? -eq 0 ]; then
  echo "Build successful! Distributing to Firebase..."
  # Locate the generated IPA file
  IPA_PATH=$(find build/ios/ipa -name "*.ipa" | head -n 1)

  if [ -z "$IPA_PATH" ]; then
    echo "Could not find .ipa file in build/ios/ipa/"
    exit 1
  fi

  firebase appdistribution:distribute "$IPA_PATH" \
    --app 1:47100126669:ios:dbd497750ab61d6ea65084 \
    --groups "testers"
else
  echo "Build failed. Distribution aborted."
fi
