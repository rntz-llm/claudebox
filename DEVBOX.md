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
devbox --allow-write ~/.npm       # widen the policy for one run
devbox --deny-read ./vendor       # ...or narrow it
devbox --why cargo build          # ...and find out what to widen it with
devbox --print-profile            # see exactly what the profile says
```

## What it allows

- **Writes** - the current directory, `$TMPDIR`, `/tmp`, `/var/tmp`, and the
  usual writable character devices. Nothing else: not your dotfiles, not
  `~/.ssh/config`, not a launch agent, not another repo. Not `.git/config` or
  `.git/hooks` either, even though they are inside the writable directory -
  see below.

- **Reads** - everything, *except* your credentials and your private data:
  `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.kube`, `~/.docker`, `~/.netrc`,
  `~/.npmrc`, `~/.config/gh`, `~/.claude` and friends; all of `~/Library`,
  which holds the keychain, your cookies and your mail, with the developer
  subtrees (`Developer`, `Caches`, `Fonts`, `Android`, `Python`, `pnpm`) given
  back; other users' home directories; `/Volumes`, because a mounted Time
  Machine disk is a copy of your home directory. `stat` is permitted
  everywhere, so path-walking still works.

- **IP networking** - none, unless you pass `--network=yes`. Unix-domain
  sockets stay reachable either way; denying them breaks the DNS resolver,
  syslog and the pasteboard for no gain once IP is gone.

The two lists are shaped differently on purpose. "Files my dev environment
reads" is long, personal and open-ended, and enumerating it produces a sandbox
that breaks constantly and therefore stops being used; "files that are secrets"
is short and nearly universal. Writes are the reverse: almost nothing
legitimately writes outside the repo and its caches, so denying by default
costs little and catches a lot.

The price is that a secret somewhere nobody listed stays readable. With the
network off by default that is staged exfiltration rather than exfiltration,
which is the trade being made.

Everything that is not a file or a socket - running programs, mach services,
sysctls - is permitted, because the profile is `(allow default)` with
`file-write*` and `network*` denied inside it and `file-read*` carved into.
Starting from `(deny default)` instead means naming every operation class dev
tooling needs - `process-exec`, `mach*`, `sysctl-read`, `file-map-executable`,
`pseudo-tty` - from an undocumented list that changes between releases.
(`file-map-executable` arrived in macOS 12 and broke deny-default profiles
everywhere; miss `pseudo-tty` and `tmux` stops working.) What it would close
here is `iokit-open`, `nvram*` and the camera and microphone, which TCC governs
anyway. Not worth a sandbox that breaks every autumn.

## What it doesn't stop

- **Reading a secret nobody thought to list.** The read policy is a denylist,
  so a credential in a novel location is readable. Add it to `deny-read`.

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
  there inside. Launch from a clean shell if it matters.

- **Damage inside the working directory.** The repo is writable by design. The
  two files your unsandboxed git would execute from - `.git/config`, via
  `core.fsmonitor`, `core.sshCommand` and `diff.*.textconv`, and `.git/hooks` -
  are denied, but `.envrc`, `Makefile` and `package.json` scripts are not, and
  your own tools run those later.

- **Links are not an escape, but they can surprise you.** Rules match the path
  a file resolves to, so a symlink pointing at `~/.ssh` gains nothing, and
  creating a hardlink is checked against the source for both read and write.
  The flip side: a symlinked subdirectory of the repo that really lives
  elsewhere isn't writable.

- **TCC-protected resources** (camera, microphone, Contacts, Desktop,
  Documents). Governed by your *terminal's* grants, not by this profile. If
  you've given your terminal Full Disk Access, that is inherited.

- **Kernel or sandbox escapes.** See Caveats.

## Configuring it

One file, one directive per line, `#` for a comment:

```
# ~/.config/devbox/rules
deny-read   ~/work/customer-data
allow-write ~/.cargo/registry
allow-read  ~/.claude            # I want this one readable after all
```

The four directives are the four flags: `--allow-read`, `--deny-read`,
`--allow-write`, `--deny-write`, all repeatable and all taking a path.

**Order is the policy.** Rules apply in sequence and the last one matching a
path wins, across reads and writes alike, exactly as SBPL resolves them.
`--deny-read ~/x --allow-read ~/x/pub` means what it looks like; so does the
reverse. Precedence runs lowest to highest: the built-in defaults, then the
config file, then the command line.

**Two directives imply a second.** `allow-write` also permits reads, and
`deny-read` also forbids writes, at the same position in the sequence:

| you write | you also get |
|---|---|
| `allow-write PATH` | `allow-read PATH` |
| `deny-read PATH` | `deny-write PATH` |
| `allow-read PATH` | — |
| `deny-write PATH` | — |

So a path is never writable without being readable. That isn't a convenience;
writable-but-unreadable is a state that doesn't mean anything. It breaks every
tool that opens a file `O_RDWR`, and it doesn't even keep the secret, because
`mv ~/.aws/credentials ./stolen` needs write permission at both ends and read
permission at neither. Better for the profile not to claim it.

The implication is one-directional: `deny-write` leaves reads alone, which is
what lets `.git/config` stay readable while being unwritable, and `allow-read`
grants no writes, which is what keeps `~/Library/Caches` readable but not
writable until you ask.

One consequence worth knowing: a broad `--allow-write` is also a broad
`--allow-read`. `--allow-write ~` reopens every credential deny.

The working directory is allowed early, ahead of the credential denies, so
`cd ~/.ssh && devbox` leaves `~/.ssh` shut rather than quietly reopening it —
and devbox says so rather than handing you a sandbox where nothing works.

There is deliberately no per-project config file: the repo is the thing being
contained, so it does not get to name its own exceptions.

## When something won't run

Almost always a write. `--why` runs the command and then prints the denials it
caused, which names the path:

```sh
devbox --why cargo build
# devbox: sandbox denials since 2026-09-23 14:02:11:
# ... (Sandbox) Sandbox: cargo(4812) deny(1) file-write-data /Users/me/.cargo/.package-cache
```

Three cases come up often:

- **Cargo** wants to write `~/.cargo/.package-cache` even for offline builds,
  and `~/.cargo/registry` when it fetches. Not writable by default on purpose:
  a shared package cache is a supply-chain persistence vector, and poisoning it
  reaches builds outside the sandbox too. When you need it, `devbox
  --allow-write ~/.cargo/registry --allow-write ~/.cargo/.package-cache cargo
  build`.

- **npm** wants `~/.npm`; same reasoning. Better still, `npm ci --cache
  ./.npm-cache` keeps it inside the repo.

- **Go** needs `GOCACHE` (`~/Library/Caches/go-build`) writable. Widen it, or
  keep it local with `GOCACHE=$PWD/.gocache`. Gradle, Maven, pip, SwiftPM and
  Xcode's DerivedData all have the same shape.

If you reach for the same flag twice, put it in `~/.config/devbox/allow-write`.

## Caveats

- **Partly tested.** It runs: the profile compiles, `sandbox-exec` executes the
  command, and the file rules behave as described - reads and writes outside
  the policy are denied, and link creation is checked against the source. Not
  yet exercised: the network stanza, where SBPL's spelling for unix-socket
  filters has varied across releases; `--why`; and any real toolchain end to
  end. The profile is generated rather than hand-maintained, and
  `--print-profile` shows exactly what `sandbox-exec` will be handed; if it
  fails to compile, `sandbox-exec` refuses to run the command at all - it fails
  closed.

- **`sandbox-exec` is deprecated.** It has carried the notice since macOS 10.10
  and still works in current releases; the underlying Seatbelt machinery is
  what App Sandbox uses. Apple provides no supported replacement for wrapping
  an arbitrary command, so the alternatives are this, a VM, or nothing.

- **macOS only.** Anywhere else the script exits rather than running your
  command unsandboxed.
