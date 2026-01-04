#!/usr/bin/env bash
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Install Homebrew first: https://brew.sh/"
  exit 1
fi

echo "Installing kind, kubectl, and helm via Homebrew..."
brew install kind kubectl helm

echo "Installed versions (see docs/k8s/README.md for recommended pins):"
kind version
kubectl version --client
helm version
