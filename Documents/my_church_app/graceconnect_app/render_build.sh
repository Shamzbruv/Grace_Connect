#!/usr/bin/env bash

# Exit on error
set -o errexit

echo ">>> Downloading Flutter..."
git clone https://github.com/flutter/flutter.git -b stable $HOME/flutter
export PATH="$PATH:$HOME/flutter/bin"

echo ">>> Verifying Flutter installation..."
flutter --version

echo ">>> Building Flutter Web..."
flutter build web --dart-define=HF_API_KEY="${HF_API_KEY}" --release

echo ">>> Build complete!"
