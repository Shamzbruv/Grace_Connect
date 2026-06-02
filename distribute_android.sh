#!/bin/bash

echo "Building Android APK..."
flutter build apk --release

if [ $? -eq 0 ]; then
  echo "Build successful! Distributing to Firebase..."
  firebase appdistribution:distribute build/app/outputs/flutter-apk/app-release.apk \
    --app 1:47100126669:android:a6100cb15fd1a070a65084 \
    --groups "testers"
else
  echo "Build failed. Distribution aborted."
fi
