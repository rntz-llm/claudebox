# Python rewrite follow-ups

Delete this file before merging.

- `container` and `claude` still resolve via PATH. A fake `container` gets the
  token's mount path and can read it. Pin `/usr/local/bin/container` if its
  install location is reliable.
- Verify managed settings: after rebuilding, `/sandbox` in a box should show the
  managed `denyRead` paths merged with the project's, not replacing them.
- `token set`: try `security add-generic-password -X <hex>` to avoid quoting the
  token; then `TOKEN_SAFE` can shrink to a paste-sanity nudge. Needs a Mac.
- Pick a container name with one `container list` call instead of up to 100
  `container inspect` calls.
- `image_exists`: `container image inspect claude` instead of `grep '^claude\b'`,
  which also matches `claude-foo`.
- Read the keychain after the `container` checks, so a missing `container`
  fails before any keychain prompt.
- `keychain_get_token` returns `None` when `/usr/bin/security` is missing;
  its annotation says `-> str`.
