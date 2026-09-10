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

# Arguments are passed through untouched, --name included: if you supplied one
# that's the name, and a name that's already taken is `container run`'s
# complaint to make, not ours. Only when there's no --name do we pick one, so
# that concurrent boxes don't collide.
name_given=no
for arg in "$@"; do
    case "$arg" in
        --name|--name=*) name_given=yes; break ;;
    esac
done

if [[ "$name_given" == no ]]; then
    for candidate in claude claude{1..99}; do
        if ! container inspect "$candidate" >/dev/null 2>&1; then
            name="$candidate"
            break
        fi
    done
    if [[ -z "${name:-}" ]]; then
        echo "Refusing to run: ‘claude’ through ‘claude99’ are all taken; pass --name." >&2
        exit 1
    fi
    echo "Container name: ‘${name}’"
    container_options+=(--name "$name")
fi

# Not echoing b/c "-e GH_TOKEN=..." is common, don't want that PAT displayed.
#echo container run "${container_options[@]}" "$@" claude
container run "${container_options[@]}" "$@" claude
