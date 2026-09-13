# devbox

`bin/devbox` runs a command against the current directory inside a macOS
sandbox, so that code in the repo — git hooks, build scripts, `npm postinstall`,
a dependency that isn't what it claims — has a much smaller blast radius than
your logged-in user.

```sh
cd ~/src/someones-repo
devbox                            # a shell, sandboxed
devbox cargo test                 # one command
devbox --network=yes npm ci       # when a step genuinely needs the network
devbox --allow-read ~/.zshrc      # widen the read allowlist
devbox --print-profile            # see exactly what the profile says
```

## What it takes away

Three things, chosen because they're the ones that turn "bad code ran" into
"bad code did lasting damage":

- **Writes** — allowed in the current directory, `$TMPDIR`, `/tmp` and
  `/var/tmp`, plus the usual writable character devices. Nothing else. No
  editing your dotfiles, your `~/.ssh/config`, your shell rc, a launch agent, or
  another repo.
- **Reads of your home directory** — everything under `/Users` is denied, with
  an allowlist for the toolchain config that tools need in order to work:
  `~/.gitconfig`, `~/.gitexclude`, `~/.config/git`, `~/.rustup`, `~/.cargo`, and
  the directory the command you asked for lives in. Metadata (`stat`) is
  permitted throughout so that path-walking works. Credentials in
  `~/.aws`, `~/.ssh`, `~/.netrc`, the login keychain and so on are unreadable.
- **IP networking** — denied by default, `--network=yes` to allow. Unix-domain
  sockets stay reachable, because denying them breaks the local plumbing (the
  DNS resolver, syslog, pasteboard) for no gain when IP is already gone.

Everything else is permitted. The profile is `(allow default)` with those three
subtractions.

## What it does not take away

Be clear-eyed about this; it is a speed bump on a slope, not a wall.

- **Reading anything world-readable outside your home directory.** `/usr`,
  `/opt/homebrew`, `/Library`, other users' public dirs.
- **Anything reachable with the network on.** `--network=yes` re-opens
  exfiltration. See below.
- **Running programs, spawning processes, using every mach service the system
  offers.** A deny-by-default profile would close most of that, at the cost of a
  long allowlist that breaks on every macOS update — see "Why allow-default".
- **Damage inside the working directory.** The repo is writable, by design: a
  malicious hook can still corrupt the repo, or plant something in it that
  bites you later, outside the sandbox.
- **Symlink escapes from the working directory.** The rules apply to resolved
  paths, so a symlink in the repo pointing at `~/.ssh` doesn't grant access —
  but equally, a symlinked subdirectory of the repo that lives elsewhere is not
  writable, which can surprise you.
- **TCC-protected resources** (camera, microphone, Contacts, Desktop,
  Documents). Those are governed separately, by the *terminal's* TCC grants, not
  by this profile. If you've granted your terminal Full Disk Access, that grant
  is inherited; the file rules here still apply, but don't rely on this to
  contain something that abuses a TCC grant your terminal already has.
- **Kernel or sandbox escapes.** `sandbox-exec` is not a security boundary Apple
  supports for this purpose; see "Caveats".

## The credentials problem

`git push` and `git pull` need the network, and once a process has the network,
"can it exfiltrate your GitHub credentials?" becomes hard rather than
impossible. Denying reads under `/Users` keeps a `--network=yes` process away
from `~/.ssh` and from `gh`'s token in `~/.config/gh`, and it can't reach
`ssh-agent` (whose socket lives under `/private/tmp/com.apple.launchd.*` —
allowed, so agent forwarding *does* work if you want it, which is exactly the
trade-off to think about before turning the network on).

The practical stance: run the untrusted parts (builds, tests, hooks, installs)
with the network off, and do your `push`/`pull` from a normal shell outside
`devbox`. That leaves git's own hook execution during `push` unsandboxed, which
is a real gap — a `pre-push` hook is repo-supplied code. Mitigate with
`git -c core.hooksPath=/dev/null push`, or by running the push under `devbox
--network=yes` and accepting the exposure.

Unsolved, and deliberately so. Any sandbox is an improvement over no sandbox.

## Why allow-default

A `(deny default)` profile is genuinely stronger, and it's what you'd want if
this were a product. It also needs a large allowlist — `process-exec`,
`mach-lookup` for a dozen system services, `sysctl-read`, `file-read` of
`/usr`, `/System`, `/Library`, the dyld shared cache, `/dev/dtracehelper` — and
that allowlist is undocumented, version-specific, and breaks whenever macOS
moves something. The failure mode is a tool dying with an inscrutable error at
an unpredictable moment, which in practice means you stop using the sandbox.

Starting from `(allow default)` inverts that trade: what it blocks is exactly
the list above and nothing more, but it blocks it reliably, and ordinary dev
tooling just works. Given a threat model of "prompt-injected LLM writes a
malicious git hook" and "a dependency does something it shouldn't", that's the
right end of the trade for now.

If you want the strong version later, the shape is the same script emitting a
different profile, with `--strict` selecting it.

## Extending it

`--allow-read PATH` and `--allow-write PATH` are repeatable and take effect
after the denies, so they carve holes in them. Two cases come up often enough to
call out:

- **Cargo** wants to write `~/.cargo/.package-cache` (a lock file) even for
  offline builds, and `~/.cargo/registry` when it fetches. Neither is writable
  by default, deliberately: a shared package cache is a supply-chain persistence
  vector, and poisoning it would affect builds outside the sandbox too. If a
  build needs it: `devbox --allow-write ~/.cargo/registry --allow-write
  ~/.cargo/.package-cache cargo build`.
- **npm** similarly wants `~/.npm`. Same reasoning, same fix. `npm ci
  --cache ./.npm-cache` keeps it inside the repo instead, which is better.

Shell rc files aren't readable either, so `devbox` gives you a bare prompt. Add
`--allow-read ~/.zshrc` (and whatever it sources) if you'd rather have your
config than the isolation. `DEVBOX=1` is exported inside, so a prompt can say
so.

The defaults live in two arrays near the top of `bin/devbox` (`default_read`,
`default_write`); edit them if a widening is permanent for you rather than
per-invocation.

## Caveats

- **Untested.** Written and reviewed, but not yet run on macOS — this repo's
  agent works inside a Linux container. The profile is generated, not
  hand-maintained, and `--print-profile` shows you what will be handed to
  `sandbox-exec`. Expect to iterate on the network stanza in particular: SBPL's
  spelling for unix-socket filters has varied across releases, and if the
  profile fails to compile `sandbox-exec` refuses to run the command at all,
  which at least fails closed.
- **`sandbox-exec` is deprecated.** It has carried a deprecation notice since
  macOS 10.10 and still works in current releases; the underlying Seatbelt
  machinery is what App Sandbox uses. Apple provides no supported replacement
  for wrapping an arbitrary command, so the alternatives are this, a VM, or
  nothing.
- **macOS only.** On anything else the script exits rather than running your
  command unsandboxed.
