#!/usr/bin/env bash
# Packages a release. Since activation moved to seller-signed licenses
# (PRODUCT.md §3.10), a build no longer carries a key table: the public key it
# verifies against is baked into lib/features/activation/activation_public.dart,
# so rebuilding is all this script has to do. Issue keys with tools/keygen.html.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter build appbundle --release
flutter build apk --release --split-per-abi

echo
echo "Sign keys with tools/keygen.html — its public key must match"
echo "lib/features/activation/activation_public.dart."
