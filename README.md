Use Apple containers to sandbox Claude in a lightweight VM with network access and `sudo`
to install tools. Made for my own use; may or may not work for you.

Put `bin/` on your `PATH`. Then `claudebox` runs a Debian container with the current
directory ("project") mounted as `/workspace`. Each project's Claude state (memories,
transcripts, login) persists in `~/.local/state/claudebox/projects/`, keyed by the project
path. `claudebox-gc` lists projects and cleans up after ones you've deleted or moved.

The first `claudebox` run builds the container image; see `Dockerfile`. Use `buildbox` to
(re)build the image explicitly.

**Things you might use instead:**

- [smol machines](https://www.smolmachines.com/): Same idea - hardware-isolated linux VMs - but it also
  works on Linux hosts via KVM. Has a cloud service ($10+/mo).

- [exe.dev](https://exe.dev/): persistent cloud VMs, $20+/mo, includes LLM tokens. Seems to have
  thought about LLM integration and security; may have some story about preventing
  exfiltration of auth tokens on prompt injection. Check yourself.
