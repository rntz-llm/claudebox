#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cwd="$(pwd -P)"

# ---------- ARGUMENTS ----------
# Everything is passed through to `container run` except --name, which we
# consume: we have to know the name to check that it is free, and to pick one
# ourselves when it is absent.

name=""
run_args=()
while (( $# )); do
    case "$1" in
        --name)
            if (( $# < 2 )); then
                echo "--name needs an argument." >&2
                exit 1
            fi
            name="$2"
            shift 2
            ;;
        --name=*)
            name="${1#--name=}"
            shift
            ;;
        *)
            run_args+=("$1")
            shift
            ;;
    esac
done

if [[ -n "$name" && ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
    echo "Refusing to use ‘${name}’ as a container name: use letters, digits, ‘_’, ‘.’ and ‘-’, starting with a letter or digit." >&2
    exit 1
fi
# ---------- END ARGUMENTS ----------

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

# A name the user asked for is used as-is: silently running under a different
# one defeats the point of asking. Without --name, take the first free
# claude/claude2/... so concurrent boxes don't collide.
if [[ -n "$name" ]]; then
    if container inspect "$name" >/dev/null 2>&1; then
        echo "Refusing to run: a container named ‘${name}’ already exists. Remove it with ‘container rm ${name}’, or pick another --name." >&2
        exit 1
    fi
else
    for i in "" $(seq 2 99); do
        if ! container inspect "claude$i" >/dev/null 2>&1; then
            name="claude$i"
            break
        fi
    done
    if [[ -z "$name" ]]; then
        echo "Refusing to run: containers ‘claude’ through ‘claude99’ all exist. Remove some, or pass --name." >&2
        exit 1
    fi
fi

echo "Container name: ‘${name}’"

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
    --name "$name"
)

# Not echoing b/c "-e GH_TOKEN=..." is common, don't want that PAT displayed.
#echo container run "${container_options[@]}" "${run_args[@]}" claude
container run "${container_options[@]}" ${run_args[@]+"${run_args[@]}"} claude
