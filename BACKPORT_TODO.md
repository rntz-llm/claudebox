# Backport candidates from the Python rewrite (python-rewrite branch)

Delete this file before merging.

- Managed settings: move the token/.credentials.json denies from
  image/claude-settings.json to /etc/claude-code/managed-settings.json (commit
  e0cac2b applies as-is). The entrypoint's jq merge replaces arrays, so a
  project with its own permissions.deny loses them; drop the README caveat.
- Call `/usr/bin/security`, not `security`: PATH may be shaped by the project dir.
- `token set`: read the token back after `security -i` and compare, since
  `%q` quoting vs security's parser is a guess. Maybe refuse chars outside
  `[A-Za-z0-9._~+/=:-]`, or try `add-generic-password -X <hex>`.
- claudebox: after creating a token, use it instead of reading the keychain again.
- `mkdir -p "$state_dir/claude"` with umask 077: it holds transcripts.
- remove_login_credential: sync the temp file before `mv`.
- Refuse a relative XDG_STATE_HOME (bad --mount source).
- claudebox-gc [m]ove: apply claudebox's workspace checks (comma/equals, home
  dir, owner) to the new path; exit 1 cleanly when /dev/tty is unavailable.
- `read` at EOF exits under `set -e`; treat as "no".
- `grep -q '^claude\b'` also matches an image named `claude-foo`.
