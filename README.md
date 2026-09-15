Use Apple containers to sandbox Claude in a lightweight VM with network access and `sudo`
to install tools. Made for my own use; may or may not work for you.

Put `bin/` on your `PATH`. Then `claudebox` runs a Debian container with the current
directory ("project") mounted as `/workspace`. Each project's Claude state (memories,
transcripts, login) persists in `~/.local/state/claudebox/projects/`, keyed by the project
path. `claudebox-gc` lists projects and cleans up after ones you've deleted or moved.

The first `claudebox` run builds the container image; see `Dockerfile`. Use `buildbox` to
(re)build the image explicitly.
