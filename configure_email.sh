#!/bin/bash
# Script to configure email credentials and deploy functions

echo "Setting Firebase Functions configuration..."
if [ -z "$GMAIL_EMAIL" ] || [ -z "$GMAIL_APP_PASSWORD" ]; then
  echo "Set GMAIL_EMAIL and GMAIL_APP_PASSWORD before running this script."
  exit 1
fi

firebase functions:config:set \
  gmail.email="$GMAIL_EMAIL" \
  gmail.app_password="$GMAIL_APP_PASSWORD"

echo "Deploying Functions..."
firebase deploy --only functions

echo "Done! Please test the support ticket functionality."
