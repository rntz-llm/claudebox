# devbox: read/write policy change - IMPLEMENTED

Implemented on the `devbox` branch: the Python port, then this change.
Kept as the record of why the policy is shaped the way it is, and of what
was tested to get there. `DEVBOX.md` is the user-facing documentation.

Deviations from the plan as written, all decided in review:

- `--strict-reads` not added; deferred until something needs it.
- `--unsafe-read-anything` removed rather than kept: with reads allowed by
  default there is nothing for it to cancel, and `--allow-read PATH` is the
  targeted escape.
- `~/Library` denied wholesale with the developer subtrees given back,
  rather than the enumerated list of stores below. Highest secret density,
  least enumerable.
- The `/System/Volumes/Data` both-spellings work turned out to be
  unnecessary; see the firmlink section.

- Resolution failures are split into "missing" and "broken". A deny is
  emitted whether or not its target exists; a broken path -- a symlink loop,
  an unreadable parent -- is fatal wherever it appears. Silently skipping an
  unresolvable rule was safe when every rule was an allow, and stopped being
  safe once denies existed: repo code could delete the `.git/hooks` deny by
  making that path a symlink loop, since the working directory is the one
  place it can write.

---

Not implemented. This records the design and the reasoning so it can be picked
up later.

## The change

Today reads are deny-by-default with an allowlist. That protects well and is
unpleasant to use: `zsh` can't read your dotfiles, so you get a bare prompt, and
the allowlist that would fix it is long, personal and endless. A sandbox you
avoid reaching for protects nothing.

Flip reads, keep writes:

| | today | planned |
|---|---|---|
| reads | deny, with allowlist | **allow, with denylist** |
| writes | deny, with allowlist | deny, with allowlist (unchanged) |
| network | off unless `--network=yes` | unchanged |

The two lists do different jobs. "Files my dev environment reads" is long,
personal and open-ended; "files that are secrets" is short, universal and
nearly stable. Enumerate the second. Writes stay strict because deny-by-default
costs almost nothing there — nothing legitimately writes outside the repo and
its caches, and when something does you hit it once and add a line.

With the network off by default, a read is staged exfiltration rather than
exfiltration, which is what makes relaxing reads defensible while relaxing
writes would not be.

## Configuration

Two files, one path per line, `#` comments, blank lines ignored, `~` expanded:

```
${XDG_CONFIG_HOME:-~/.config}/devbox/deny-read
${XDG_CONFIG_HOME:-~/.config}/devbox/allow-write
```

- Entries **add to** the built-in defaults rather than replacing them.
- A `!` prefix removes a default (gitignore-style), emitted as an `allow` after
  the denies. This is what lets someone un-deny `~/.claude` without editing the
  script.
- **Never read config from the repo.** No `.devbox` file in the working
  directory: the repo is the thing being contained, and letting it name its own
  exceptions defeats the point.
- The config directory is itself in the read denylist by default — it tells an
  attacker exactly which paths are protected.

Per-invocation `--allow-read` / `--allow-write` stay as they are.

## Sensible defaults: read denylist

Credentials and keys:

```
~/.ssh  ~/.gnupg  ~/.aws  ~/.azure  ~/.config/gcloud  ~/.kube  ~/.docker
~/.netrc  ~/.authinfo  ~/.authinfo.gpg  ~/.password-store  ~/.terraform.d
~/.npmrc  ~/.pypirc  ~/.gem/credentials  ~/.cargo/credentials.toml
~/.config/gh  ~/.config/glab-cli  ~/.config/op  ~/.1password
~/.claude  ~/.config/anthropic  ~/.local/share/keyrings
```

macOS stores:

```
~/Library/Keychains  ~/Library/Cookies  ~/Library/Safari  ~/Library/Messages
~/Library/Mail  ~/Library/Group Containers
~/Library/Application Support/{Google/Chrome,Firefox,BraveSoftware}
~/Library/Application Support/AddressBook
```

Outside `$HOME`:

```
/Volumes                  # a mounted Time Machine disk is a copy of $HOME
/Users                    # other users' homes; $HOME is re-allowed after
/private/var/db/dslocal
```

Optional regex denies, worth trying and dropping if they cause trouble:
`id_(rsa|dsa|ecdsa|ed25519)`, `\.pem$`, `\.p12$`. Note `\.env$` is deliberately
absent — it would fire on the repo's own `.env`, and the repo is allowed last
anyway, but the ordering is easy to get wrong.

## Sensible defaults: write allowlist

```
$cwd                      # resolved, and $cwd only
$TMPDIR                   # resolved explicitly, NOT all of /private/var/folders
/private/tmp  /private/var/tmp
/dev/null /dev/zero /dev/random /dev/urandom /dev/tty /dev/ptmx
/dev/dtracehelper  /dev/fd  ^/dev/ttys[0-9]+$
```

Deliberately *not* included, because they are code that later executes outside
the sandbox: `~/.cargo/registry`, `~/.cargo/.package-cache`, `~/.npm`,
`~/Library/Caches/go-build`, `~/.gradle`, `~/.m2`. These are the most common
reason a build fails, so DEVBOX.md should give the exact lines to paste into
`allow-write` rather than making people work it out.

### Proposed, needs a decision

Deny writes to `$cwd/.git/hooks` and `$cwd/.git/config` even though `$cwd` is
writable. Three lines, and it closes the cheapest escape there is: a hook or a
`core.fsmonitor` / `core.sshCommand` / `diff.*.textconv` entry that your *next*
unsandboxed `git status` runs. claudebox already mounts both read-only, so
there's precedent. Cost: `git config` and `git remote add` stop working inside
the sandbox. Needs a `!`-style opt-out.

## Profile rule order

SBPL is last-match-wins, so the order carries the meaning:

```scheme
(allow default)

;; writes
(deny file-write*)
(allow file-write* <allowlist>)          ; cwd, TMPDIR, tmp, config additions
(allow file-write* <device nodes>)
(deny file-write* <.git/hooks, .git/config>)   ; after the cwd allow

;; reads
(deny file-read* (subpath "/Users"))     ; other users
(allow file-read* (subpath "$HOME"))     ; ...but yours is fine
(deny file-read* <denylist + config>)
(deny file-read* <same entries, /System/Volumes/Data-prefixed>)
(allow file-read* <config ! negations>)
(allow file-read* (subpath "$cwd"))      ; LAST: the repo can always read itself
(allow file-read-metadata)               ; stat everywhere, for path-walking
```

## Holes this design depends on closing

Under an allowlist a missed entry fails closed and you notice. Under a denylist
a missed entry fails open and you don't. One consequence, since tested and
fixed; the other two path questions turned out to need no action.

1. **Symlinked files in our own lists.** Confirmed on macOS. Seatbelt matches
   the *resolved target*, which is the direction we want — a symlink in the
   repo pointing at `~/.ssh` launders nothing. But it means our list entries
   have to name targets, and `resolve()` doesn't:

   ```sh
   # ~/t/link -> ~/t/canary
   devbox --allow-read ~/t/link   cat ~/t/link   # denied
   devbox --allow-read ~/t/canary cat ~/t/link   # works
   # Sandbox: cat deny(1) file-read-data /Users/me/t/canary
   ```

   Scope is narrow: `[[ -d "$p" ]]` follows symlinks, so a symlinked
   *directory* already resolves correctly via `cd … && pwd -P`
   (`~/.ssh -> ~/Dropbox/ssh` is fine). Only symlinks to **files** keep the
   link path, because that branch rebuilds from `dirname` + `basename`.

   Today that is a usability bug — `~/.gitconfig -> ~/dotfiles/gitconfig` is
   silently unreadable and git just doesn't see your config. After the flip it
   is a leak, for exactly the file-shaped denylist entries that dotfile
   managers symlink: `~/.netrc`, `~/.npmrc`, `~/.pypirc`,
   `~/.cargo/credentials.toml`.

   **Fixed in `bin/devbox`** (independently of the flip): `resolve()` now
   follows a trailing symlink before the `-d` test, bounded at 32 hops, and
   errors on a cycle rather than emitting the link path. Absolute, relative and
   chained links resolve to the target; links to directories and broken links
   (a cache a tool will create) keep working as before.

### Firmlink aliases: tested, no action needed

Seatbelt matches the kernel's canonical path for the file, not the string the
process passed. Confirmed: with an explicit
`(deny file-read* (subpath "~/t/canary"))`, both spellings are denied, and both
log lines name the short form even though one `cat` was given the long one:

```
Sandbox: cat(73188) deny(1) file-read-data /Users/me/t/canary   # asked for ~/t/canary
Sandbox: cat(73208) deny(1) file-read-data /Users/me/t/canary   # asked for /System/Volumes/Data/...
```

Reading an allowed path through the alias works for the same reason. So denies
need only one spelling, and there is nothing to derive from
`/usr/share/firmlinks`.

This is the same rule the symlink result showed, and it also retroactively
justifies the script writing `/private/tmp` and `/private/var/tmp` rather than
`/tmp` and `/var/tmp`.

### rename(2): tested, and it is why write implies read

`mv` out of a write-allowed, read-denied directory succeeds and the bytes
land somewhere readable. Verified on macOS with a hand-built profile:

```sh
(allow file-write* (subpath "$HOME/t/ro"))
(deny  file-read*  (subpath "$HOME/t/ro"))
# cat ~/t/ro/creds        -> denied
# mv ~/t/ro/creds ./stolen && cat ./stolen   -> SECRET
```

So rename needs write at both ends and read at neither, unlike `link`, which
is checked for both on the source. Writable-but-unreadable therefore never
preserved secrecy; it only looked like it did. That is the justification for
`allow-write` implying `allow-read`, and for the contrapositive
`deny-read` implying `deny-write`: the profile should not be able to state
something that isn't true.

Consequence to keep in mind: anything you make writable is effectively
readable, whether or not a read rule says so.

Still to check: `deny-write` on `$cwd/.git/config` has to withstand the same
trick. `mv .git/config /tmp/x` needs write on the source *path*, which is
denied, while `.git/` itself is writable -- but that is an inference from the
test above, not a measurement.

### subpath: tested, matches a plain file

`(subpath "/path/to/file")` covers the file itself, so the file-shaped
denylist entries -- `~/.netrc`, `~/.npmrc`, `~/.pypirc`, `~/.authinfo`,
`~/.gem/credentials`, `~/.cargo/credentials.toml` -- work as written. No need
for `literal`. Verified with `devbox --deny-read ~/t/canary sh -c 'cat
~/t/canary'`, which is denied.

### Hardlinks: tested, closed, no action needed

Link creation checks **both read and write on the source**, so it can never
grant more access than you already had. Confirmed on macOS:

```
# source neither readable nor writable -> fails the read check
Sandbox: ln deny(1) forbidden-link-priv<file-read*>  ~/t/canary  <cwd>/leak
# source readable (--allow-read) but not writable -> fails the write check
Sandbox: ln deny(1) forbidden-link-priv<file-write*> ~/t/ro/file <cwd>/file
```

This matters because the obvious attack against the flip is aliasing rather
than reading: `ln ~/.zshrc ./z && echo … >> ./z` writes through a path inside
`$cwd`, which is allowed. The write check on the source blocks it. Writes stay
deny-by-default under the flip, so it stays blocked.

No `(deny file-link)` rule is needed, which also avoids breaking pnpm,
`cp -l` and `git clone --local`.

(A third denial seen during testing, `System Policy: ... file-link /bin/sh`,
is not ours: `ln /bin/sh x` fails outside devbox too, because macOS refuses to
hardlink system binaries. It does confirm `file-link` is a usable operation
name if one is ever wanted.)

Also adjust: the working-directory guard must refuse a `$cwd` that falls under
any read-deny default, since the final `(allow file-read* (subpath "$cwd"))`
would otherwise override it. `cd ~/.ssh && devbox` should be an error.

## Flags

- `--unsafe-read-anything` becomes meaningless and should be removed; reads are
  allow-by-default.
- Add `--strict-reads` selecting today's allowlist profile, for when you're
  about to run something you actively distrust. Both code paths exist already;
  it's the same machinery with the default flipped.
- `--network`, `--allow-read`, `--allow-write`, `--why`, `--print-profile`
  unchanged.

## Not in scope

Deliberately left alone, and unchanged by this: the login keychain is reachable
through `securityd`, `ssh-agent` and `/var/run/docker.sock` are reachable over
unix sockets, the environment passes through with whatever tokens your shell
exported, and `open -a` / `launchctl submit` start processes outside the
sandbox. See DEVBOX.md.

A `--remember` flag that appends to `deny-read` / `allow-write` from what
`--why` reports is the obvious follow-up, and is explicitly deferred.
