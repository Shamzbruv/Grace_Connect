#!/usr/bin/env bash

# Exit on error
set -o errexit

if [ ! -d "$HOME/flutter" ]; then
  echo ">>> Downloading Flutter..."
  git clone https://github.com/flutter/flutter.git -b stable $HOME/flutter
else
  echo ">>> Flutter already exists in cache."
fi

export PATH="$PATH:$HOME/flutter/bin"

echo ">>> Verifying Flutter installation..."
flutter --version

echo ">>> Moving to app directory..."
# We are already in the app directory because the Render build command did `cd Documents/my_church_app/graceconnect_app` before executing this script.

echo ">>> Building Flutter Web..."
flutter build web --dart-define=HF_API_KEY="${HF_API_KEY}" --release

echo ">>> Build complete!"
