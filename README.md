Some tools for setting up an Apple container to sandbox Claude in a lightweight VM while
giving it network access and the ability to install tools it needs.

Put `bin/` on your `PATH`. Then `claudebox`, run from the project you want to work in,
runs a container with the current directory as `/workspace`; `buildbox` rebuilds the
image.

Each project's Claude state (memories, transcripts, login) persists in
`~/.local/state/claudebox/projects/`, keyed by the project's path. `claudebox-gc` lists
it and cleans up after projects you've deleted or moved.
