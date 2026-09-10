#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cwd="$(pwd -P)"

# ---------- WORKSPACE (CURRENT) DIRECTORY MUST BE REASONABLE ----------
# 1. No commas or equals signs (they'd break --mount's option syntax).
# 2. No home dirs or parents of homedirs.
# 3. Not the claudebox.sh directory or one of its ancestors.
# 4. Must be owned by current user.

if [[ "$cwd" == *[,=]* ]]; then
    echo "Refusing to mount ‘${cwd}’ as /workspace: its path contains a comma or equals sign, which --mount cannot express." >&2
    exit 1
fi

# Is $1 the same directory as $2, or one of its ancestors?
is_same_or_ancestor() {
    local ancestor="${1%/}" path="${2%/}"
    [[ "$path" == "$ancestor" || "$path" == "$ancestor"/* ]]
}

if is_same_or_ancestor "$cwd" "$script_dir"; then
    if [[ "$cwd" == "$script_dir" ]]; then
        echo "Refusing to mount claudebox.sh's own directory as /workspace." >&2
    else
        echo "Refusing to mount ‘${cwd}’ as /workspace: it contains claudebox.sh's own directory." >&2
    fi
    exit 1
fi

# On macOS every home directory is /Users/<name>, so anything at or above that
# level is either a home directory or holds all of them.
case "$cwd" in
    /Users/*/*) ;;  # somewhere inside a home directory: fine
    /|/Users|/Users/*)
        echo "Refusing to mount ‘${cwd}’ as /workspace: mount a project directory, not a home directory or the root of the filesystem." >&2
        exit 1
        ;;
esac

if [[ ! -O "$cwd" ]]; then
    echo "Refusing to mount ‘${cwd}’ as /workspace: it is owned by ‘$(stat -f %Su "$cwd")’, not ‘$(id -un)’." >&2
    exit 1
fi
# ---------- END WORKSPACE DIR CHECKS ----------

if container image list | grep -q '^claude\b'; then
    echo "Image ‘claude’ already built, reusing."
else
    # --no-cache because the Dockerfile pins neither node nor rust, and a cached
    # layer would keep whatever version it first resolved. See
    # BUILD_CACHING_IS_PROBLEMATIC.md.
    "$script_dir/buildbox.sh" --no-cache
fi

container_options=(
    --interactive
    --tty
    --mount "type=bind,source=$cwd,target=/workspace"
)

# TODO: let user supply a name via --name.
for n in claude claude2 claude3; do
    if ! container inspect "$n" >/dev/null 2>&1; then
        echo "Container name: ‘${n}’"
        container_options+=(--name "$n")
        break
    fi
done

# Not echoing b/c "-e GH_TOKEN=..." is common, don't want that PAT displayed.
#echo container run "${container_options[@]}" "$@" claude
container run "${container_options[@]}" "$@" claude
