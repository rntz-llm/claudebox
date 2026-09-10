# Build caching is problematic

**TL;DR.** The Dockerfile deliberately doesn't pin Node or Rust — both resolve to the current LTS/stable at build time. But a layer's cache key is computed from the *text* of the instruction, never from what the command fetches, so those layers hash to the same key forever and BuildKit reuses them without ever re-running the `curl` that would find a newer version. The result is accidental pinning: the image is stuck on whatever was current the last time that layer genuinely built, with nothing in git recording which version that was — no freshness *and* no reproducibility. Worse, `container image rm claude` is not on its own enough, because the build cache lives in the builder VM rather than the image store, so deleting the image and rebuilding just reconstructs it from the same stale layers. `claudebox.sh` therefore passes `--no-cache`; reach for that flag too when building by hand.

## The mechanism

A layer's cache key comes from the text of the instruction plus the parent layer's ID — never from what the command actually fetches when it runs. So this instruction:

```dockerfile
RUN set -eux; \
    version="$(curl -fsSL https://nodejs.org/dist/index.json \
      | jq -r '[.[] | select(.lts != false)][0].version')"; \
    ...
```

hashes to the same key forever. BuildKit sees a cache hit and reuses the layer without executing anything, so the `curl` that would discover a newer LTS never runs. Same for the rustup layer.

## Why that's the worst of both worlds

You end up accidentally pinned — to whatever version happened to be current the last time that layer genuinely built:

- **No freshness.** The Dockerfile says "current LTS" but the image keeps Node 24.21.0 indefinitely.
- **No reproducibility either.** Someone building fresh next year gets a different Node, and nothing in git records which one either build got. An explicit `v24.21.0` would at least be honest and auditable.

And the update, when it eventually comes, arrives as a side effect of something unrelated. Edit the apt line and every layer below it invalidates, so Node and Rust silently jump versions in a commit about adding a package. That's a confusing way to find out your toolchain moved.

## The part that bites a manual-rebuild workflow

Build cache lives in the builder VM, not the image store. So:

```sh
container image rm claude && container build --tag claude
```

deletes the image and then reconstructs it from the same cached layers. Feels like a clean rebuild; isn't one. You need `container build --no-cache`, or a targeted cache-bust.

This is why `claudebox.sh` builds with `--no-cache`. Deleting the image and re-running `./claudebox.sh` is a genuine fresh build; the trap above only applies when invoking `container build` directly.

The same applies to `RUN curl -fsSL https://claude.ai/install.sh | bash` — that layer pins the Claude Code version the same way. Less critical, since the installed binary self-updates at runtime, but a from-scratch build on a cold cache will pull a much newer Claude than a cache-hit build.

## If you want to fix it

Roughly in order of preference:

1. **Leave it, and use `--no-cache` when you want fresh.** This is what we do: `claudebox.sh` passes `--no-cache`, so `image rm` plus a normal launch refreshes everything. The cost is that a rebuild redoes the expensive apt layer (emacs, build-essential) too.

2. **Cache-bust argument** on just the volatile layers:

   ```dockerfile
   ARG TOOLCHAIN_REFRESH=0
   RUN TOOLCHAIN_REFRESH=$TOOLCHAIN_REFRESH; set -eux; ...
   ```

   Then `--build-arg TOOLCHAIN_REFRESH=$(date +%F)` refreshes Node/Rust while keeping the expensive apt layer (emacs, build-essential) cached.

3. **Pin explicitly and bump in git.** Most reproducible, but it puts the versions back in the Dockerfile.

One structural nit worth folding into whichever option: the Node layer currently sits before `useradd`, so invalidating it rebuilds the Claude install and the whole rustup toolchain below it. Moving it after the rustup layer would shrink that blast radius considerably, at no cost.
