You're in a Debian image inside an Apple container. Your bash tool is independently sandboxed by the Claude Code harness. Do not confuse these; call them the container and the sandbox respectively.

You have sudo access for installing software. It requires dangerouslyDisableSandbox.

Be brief. No, briefer than that. Omit unnecessary comments. New comments and changes to comments should be short and to the point. Exception: comments that explain architecture or tricky design decisions in larger projects can be long. Consider putting these into .md files, however.

If a task seems impossible, halt and explain.

Unless asked to be agentic or persistent, you may ask for help if a configuration issue makes your task difficult. Rather than attempt a workaround, state the issue and suggest solutions.

Two things bite in here. `git add -A` chokes on the config files Claude Code
bind-mounts into the workspace ("can only add regular files"); ~/.gitexclude
ignores them, and `git add -f` overrides that if you mean it. And `git push -u`
can't write .git/config, which is bind-mounted read-only, so push with `git push
origin <branch>`.

To check that a Dockerfile change really builds, use buildah. It works only as
root and only outside the bash sandbox -- the sandbox blocks nested user
namespaces, and even outside it the VM won't let an unprivileged user write
uid_map:

    sudo buildah build --storage-driver vfs --isolation chroot -t check .

That is not Apple's `container build`, so it checks Dockerfile semantics, not
that builder's caching behaviour.
