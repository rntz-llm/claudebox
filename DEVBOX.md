(mostly written by Claude)

# devbox

`bin/devbox` runs a command inside a macOS sandbox, so that code in the repo - git hooks,
build scripts, `npm postinstall`, a dependency that isn't what it claims - has a smaller
blast radius. devbox's goal is to contain accidents, mistakes and opportunistic code, and
to raise the cost of everything else. It **will not resist deliberate attack**;
`bin/claudebox` is significantly stronger.

```sh
cd ~/src/someones-repo
devbox                            # a shell, sandboxed
devbox cargo test                 # one command
devbox --network=yes npm ci       # when a step genuinely needs the network
devbox --allow-read ~/.zshrc      # widen the read allowlist
devbox --why cargo test           # ...and find out what to widen it with
devbox --print-profile            # see exactly what the profile says
```

## What it allows

- **Writes** - the current directory, `$TMPDIR`, `/tmp`, `/var/tmp`, and the
  usual writable character devices. Nothing else: not your dotfiles, not
  `~/.ssh/config`, not a launch agent, not another repo.

- **Reads** - the system (`/usr`, `/bin`, `/sbin`, `/System`, `/Library`,
  `/Applications`, `/opt`, `/private/etc`, `/dev`, and the plumbing under
  `/private/var/db` and `/private/var/run`), your toolchain config
  (`~/.gitconfig`, `~/.gitexclude`, `~/.config/git`, `~/.rustup`, `~/.cargo`,
  and the directory the command you asked for lives in), the scratch
  directories above, and the current directory. Everything else is denied,
  including what nobody would think to enumerate: `~/.aws`, `~/.ssh`,
  `~/.netrc`, `~/.config/gh/hosts.yml`, a Time Machine volume under `/Volumes`,
  the `/System/Volumes/Data/Users/…` spelling of your own home directory.
  `stat` is permitted everywhere, so path-walking still works.

- **IP networking** - none, unless you pass `--network=yes`. Unix-domain
  sockets stay reachable either way; denying them breaks the DNS resolver,
  syslog and the pasteboard for no gain once IP is gone.

Files and the network are the fail-closed part. Everything else - running
programs, mach services, sysctls - is permitted, because the profile is
`(allow default)` with `file-read*`, `file-write*` and `network*` denied inside
it.

That is deliberate. Starting from `(deny default)` instead means naming every
operation class dev tooling needs - `process-exec`, `mach*`, `sysctl-read`,
`file-map-executable`, `pseudo-tty` - from an undocumented list that changes
between releases. (`file-map-executable` arrived in macOS 12 and broke
deny-default profiles everywhere; miss `pseudo-tty` and `tmux` stops working.)
What it would close here on top of the above is `iokit-open`, `nvram*` and the
camera and microphone, which TCC governs anyway. Not worth a sandbox that
breaks every autumn and stops getting used.

## What it doesn't stop

- **Starting a process outside the sandbox.** Children inherit the profile, but
  `open -a`, `launchctl submit` and Apple Events ask a system service to do the
  work, and what *it* starts is not your child. Closing this needs the
  mach-service allowlist described above, so it stays open.

- **Daemons reading files on your behalf.** The file rules bind your process.
  The login keychain is reached through `securityd`, preferences through
  `cfprefsd`, file names through Spotlight - none of those are reads by you.
  Try `git credential-osxkeychain get` before assuming your git credentials are
  out of reach.

- **Unix sockets.** `ssh-agent`'s socket sits under
  `/private/tmp/com.apple.launchd.*` and `SSH_AUTH_SOCK` is inherited, so the
  agent will sign whatever it's asked. If you run Docker, `/var/run/docker.sock`
  is reachable too, and the Docker API can mount `/` into a container. Neither
  is affected by `--network=no`.

- **Your environment.** It passes through as-is, so whatever your shell
  exported - `GITHUB_TOKEN`, `ANTHROPIC_API_KEY`, `AWS_SECRET_ACCESS_KEY` - is
  there inside. Not reading your rc files doesn't help with that; launch from a
  clean shell if it matters.

- **Damage inside the working directory.** The repo is writable by design, and
  your unsandboxed tools read it afterwards: `.git/config` alone can run
  commands via `core.fsmonitor`, `core.sshCommand` and `diff.*.textconv`, and
  then there are `.envrc`, `Makefile`, `package.json` scripts.
  `git -c core.hooksPath=/dev/null` covers hooks and nothing else.

- **Symlinks out of the repo.** Rules apply to resolved paths, so a symlink
  pointing at `~/.ssh` gains nothing - but a symlinked subdirectory of the repo
  that really lives elsewhere isn't writable, which can surprise you.

- **TCC-protected resources** (camera, microphone, Contacts, Desktop,
  Documents). Governed by your *terminal's* grants, not by this profile. If
  you've given your terminal Full Disk Access, that is inherited.

- **Kernel or sandbox escapes.** See Caveats.

## Network and credentials

`git push` and `git pull` need the network, and once a process has the network,
"can it exfiltrate my GitHub credentials?" becomes hard rather than impossible.
The read allowlist keeps `~/.ssh` and `~/.config/gh/hosts.yml` out of reach;
ssh-agent and the keychain are not covered, per above.

The practical stance: builds, tests, hooks and installs with the network off,
`push` and `pull` from a normal shell outside devbox. That leaves `pre-push` -
repo-supplied code - running unsandboxed, so
`git -c core.hooksPath=/dev/null push` if you care.

Unsolved, deliberately. Any sandbox is an improvement over no sandbox.

## When something won't run

The read allowlist is certainly missing something that some toolchain wants.
`--why` runs the command and then prints the denials it caused, which names the
path to add:

```sh
devbox --why cargo build
# devbox: sandbox denials since 2026-09-21 14:02:11:
# Sandbox: cargo(4812) deny(1) file-read-data /Users/me/.cargo/config.toml
```

`--allow-read PATH` and `--allow-write PATH` are repeatable and carve holes in
the denies; `--allow-write` permits reads of the same path too, since a
write-only directory is no use to a compiler. `--unsafe-read-anything` cancels
the read allowlist for a single invocation, for when you're blocked and need to
get on with it - writes and the network stay restricted. If you reach for it
twice for the same reason, edit the arrays instead: `system_read`,
`default_read` and `default_write`, near the top of `bin/devbox`.

Three cases come up often:

- **Cargo** wants to write `~/.cargo/.package-cache` even for offline builds,
  and `~/.cargo/registry` when it fetches. Not writable by default on purpose:
  a shared package cache is a supply-chain persistence vector, and poisoning it
  reaches builds outside the sandbox too. When you need it, `devbox
  --allow-write ~/.cargo/registry --allow-write ~/.cargo/.package-cache cargo
  build`.

- **npm** wants `~/.npm`; same reasoning. Better still, `npm ci --cache
  ./.npm-cache` keeps it inside the repo.

- **Go** fails before it starts - `GOMODCACHE` (`~/go/pkg/mod`) isn't readable
  and `GOCACHE` (`~/Library/Caches/go-build`) isn't writable. Widen both, or
  keep them local with `GOFLAGS=-modcacherw GOMODCACHE=$PWD/.gomod
  GOCACHE=$PWD/.gocache`. Gradle, Maven, pip, SwiftPM and Xcode's DerivedData
  all have the same shape.

Shell rc files aren't readable either, so you get a bare prompt. Add
`--allow-read ~/.zshrc` (and whatever it sources) if you'd rather have your
config than the isolation; `DEVBOX=1` is exported inside, so a prompt can say
so.

## Caveats

- **Untested.** Written and reviewed, but not yet run on macOS. The profile is
  generated rather than hand-maintained, and `--print-profile` shows exactly
  what `sandbox-exec` will be handed. Two places to expect iteration: the read
  allowlist, which is what `--why` is for, and the network stanza, where SBPL's
  spelling for unix-socket filters has varied across releases. If the profile
  fails to compile, `sandbox-exec` refuses to run the command at all - it fails
  closed.

- **`sandbox-exec` is deprecated.** It has carried the notice since macOS 10.10
  and still works in current releases; the underlying Seatbelt machinery is
  what App Sandbox uses. Apple provides no supported replacement for wrapping
  an arbitrary command, so the alternatives are this, a VM, or nothing.

- **macOS only.** Anywhere else the script exits rather than running your
  command unsandboxed.
