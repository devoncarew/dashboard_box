#!/bin/bash

# Fast fail the script on failures.
set -e

# Check the project.
pub global activate tuneup
pub global run tuneup check

# Re-generate the website.
pub build

# TODO: deploy to a personal staging site, based on github ID, when not
#       merging into master

if [ "$TRAVIS_PULL_REQUEST" = "false" ]; then
  if [ "$TRAVIS_BRANCH" = "master" ]; then
    echo "Deploying to Firebase."

    npm install -g firebase-tools
    firebase deploy --token "$FIREBASE_TOKEN" -f purple-butterfly-3000
  fi
fi
