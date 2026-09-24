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

Writes to current directory; reads anywhere; no network. Exceptions/details:

- **Writes**: The current directory, your per-user temp directory (`getconf
  DARWIN_USER_TEMP_DIR`, even if `$TMPDIR` points elsewhere), `/tmp`,
  `/var/tmp`, and the usual writable character devices. Not `.git/config` or
  `.git/hooks` either, even though they are inside the writable directory - see
  below. `/tmp` is shared with your unsandboxed programs, so sandboxed code can
  delete or rename their files there, `ssh-agent`'s socket included.

- **Reads**: Everything except some well-known private files: `~/.ssh`,
  `~/.gnupg`, `~/.aws`, `~/.kube`, `~/.docker`, `~/.netrc`, `~/.npmrc`,
  `~/.config/gh`, `~/.claude` and friends; all of `~/Library`, which holds the
  keychain, your cookies and your mail, with the developer subtrees
  (`Developer`, `Caches`, `Fonts`, `Android`, `Python`, `pnpm`) given back;
  other users' home directories; `/Volumes`, because a mounted Time Machine disk
  is a copy of your home directory. `stat` is permitted everywhere, so
  path-walking still works.

- **IP networking**: None, unless you pass `--network=yes`. That opens
  localhost too: Docker, databases, Chrome's debugging port.

- **Unix sockets**: syslog's, plus the DNS resolver's with `--network=yes`.
  Nothing else: sockets in shared directories reach programs that run commands
  for whoever connects - tmux, the Emacs server, VS Code. That includes
  `ssh-agent` and Docker, so `git push` over ssh won't work inside.

The read/write lists are shaped differently on purpose. "Files my dev
environment reads" is long, personal and open-ended, and enumerating it produces
a sandbox that breaks constantly and therefore stops being used; "files that are
secrets" is short and nearly universal. Writes are the reverse: almost nothing
legitimately writes outside the repo and its caches, so denying by default costs
little and catches a lot.

The price is that a secret somewhere nobody listed stays readable. Turning the
network off by default makes exfiltration only slightly harder: e.g. `open
"https://.../${SECRET}"` is not blocked. *Don't use devbox to contain serious
attackers; it won't work.*

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
  mach-service allowlist described above, so it stays open. Likewise the
  `TIOCSTI` ioctl, which types commands into your terminal for your shell to
  run once devbox exits.

- **Daemons reading files on your behalf.** The file rules bind your process.
  The login keychain is reached through `securityd`, preferences through
  `cfprefsd`, file names through Spotlight - none of those are reads by you.
  Try `git credential-osxkeychain get` before assuming your git credentials are
  out of reach.

- **Secrets that aren't files.** Your environment passes through as-is, so
  whatever your shell exported - `GITHUB_TOKEN`, `ANTHROPIC_API_KEY`,
  `AWS_SECRET_ACCESS_KEY` - is there inside. Launching from a clean shell
  doesn't hide other processes' environments, which `ps -E` shows. The
  clipboard is readable too.

- **Damage inside the working directory.** The repo is writable by design. The
  two files your unsandboxed git would execute from - `.git/config`, via
  `core.fsmonitor`, `core.sshCommand` and `diff.*.textconv`, and `.git/hooks` -
  are denied, but only those: `.git` itself can probably be swapped out, as can
  a worktree's or submodule's `.git` file, and `.git/modules/*/config` and
  nested repos are writable. So are `.envrc`, `Makefile`, `package.json`
  scripts and in-tree hook directories (husky, pre-commit, lefthook), and your
  own tools run those later. Run devbox from the repo root: from `~/src`, every
  repo in it is exposed.

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
# I want this one readable after all
allow-read  ~/.claude
```

Comments are whole lines only: a later `#` is part of the path. Config paths
needn't exist, so a typo silently does nothing; check `--print-profile`.
Relative paths resolve against the working directory. Command-line paths must
exist. Write paths in their on-disk case: matching is probably case-sensitive
even where the disk isn't.

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

**Your rules silently override the built-in ones**, and a broad
`--allow-write` is also a broad `--allow-read`. `--allow-write ~` reopens every
credential deny; `--allow-write .` reopens `.git/config` and `.git/hooks`;
`--allow-write ~/.config` lets sandboxed code rewrite your devbox rules.

The working directory is allowed early, ahead of the credential denies, so
`cd ~/.ssh && devbox` leaves `~/.ssh` shut rather than quietly reopening it —
and devbox says so rather than handing you a sandbox where nothing works.

There is deliberately no per-project config file: the repo is the thing being
contained, so it does not get to name its own exceptions.

## When something won't run

Usually a write. `--why` runs the command and then prints the denials since it
started, which names the path. They include other programs' denials, and Ctrl-C
loses the report.

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

Other causes:

- **Unix sockets**, all denied, even a tool's own: watchman, turbo and nx
  daemons, Python `multiprocessing` managers.
- **Localhost** is off with the network: Gradle and Bazel daemons, test
  servers.
- **`.git/config`** isn't writable: `git push -u`, `git remote add`, husky's
  install step. Run those outside.
- **Clang/Swift module cache** is probably not writable, breaking `-fmodules`
  and Swift builds.
- **Unreadable dev directories**: `~/Library/Java`,
  `~/Library/org.swift.swiftpm`, `~/Library/Application
  Support/{pip,pypoetry,Coursier}`. Use `--allow-read`.

If you reach for the same flag twice, put it in `~/.config/devbox/rules`.

## Caveats

**macOS only**, and even there **`sandbox-exec` is officially deprecated**.
Despite being deprecated since macOS 10.10 it still works in current releases;
the underlying Seatbelt machinery is what App Sandbox uses. Apple provides no
supported replacement for wrapping an arbitrary command, so the alternatives are
this, a VM, or nothing.
