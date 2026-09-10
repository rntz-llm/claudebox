#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Always builds; claudebox.sh only calls this when the image is missing, but run
# directly this is how you rebuild on demand. Extra arguments are passed through
# to `container build` -- `--no-cache` and `--progress plain` are the useful
# ones; see BUILD_CACHING_IS_PROBLEMATIC.md for why you usually want the former.

build_options=(
    # Identity is passed in rather than committed, to keep it out of the repo.
    --build-arg GIT_USER_NAME="$(git config --get user.name || true)"
    --build-arg GIT_USER_EMAIL="$(git config --get user.email || true)"
    --tag claude
)

echo "Building ‘claude’ image..."
echo container build "${build_options[@]}" "$@"
(cd "$script_dir" && container build "${build_options[@]}" "$@")
echo "... built ‘claude’ image!"
echo
