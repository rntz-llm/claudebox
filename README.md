Use Apple containers to sandbox Claude in a lightweight VM with network access and `sudo`
to install tools. Made for my own use; may or may not work for you.

Put `bin/` on your `PATH`. Then `claudebox` runs a Debian container with the current
directory ("project") mounted as `/workspace`. Each project's Claude state (memories,
transcripts, login) persists in `~/.local/state/claudebox/projects/`, keyed by the project
path. `claudebox-gc` lists projects and cleans up after ones you've deleted or moved.

**Auth.** `claudebox-token set` runs `claude setup-token` and stores the token it prints
in your login keychain. That token can only run models, unlike the ~30-day credential
`/login` leaves in the project's state, so a prompt injection that reads it gets much less.
`claudebox` mounts it read-only at `/run/claudebox-secrets`, and the image's `bin/claude`
hands it to Claude on a pipe; sandboxed commands are denied both it and
`.credentials.json`. With no token stored, `claudebox` offers to create one and otherwise
falls back to `/login`. A project whose `settings.json` already sets `permissions.deny`
keeps its own list, so add the `Read(//run/claudebox-secrets/**)` rule there yourself.

The first `claudebox` run builds the container image; see `Dockerfile`. Use `buildbox` to
(re)build the image explicitly.

**Things you might use instead:**

- [smol machines](https://www.smolmachines.com/): Same idea - hardware-isolated linux
  VMs - but it also works on Linux hosts via KVM. Has a cloud service ($10+/mo).

- [exe.dev](https://exe.dev/): persistent cloud VMs, $20+/mo, includes LLM tokens. Seems
  to have thought about LLM integration and security; may have some story about preventing
  exfiltration of auth tokens on prompt injection. Check yourself.
