# REQUESTS FROM USER

Be brief and to the point everywhere: chat, comments, code, .md files, PRs. Omit unnecessary comments. Exception: comments that explain architecture or tricky design decisions in larger projects can be long. Consider putting these into .md files, however.

If a task seems impossible, halt and explain.

Unless asked to be agentic or persistent, you may ask for help if a configuration problem or the container image makes your task difficult. Rather than attempt a workaround, state the issue and suggest solutions. If you do work around a problem, tell the user so they can fix it moving forward.

# CONTAINER AND SANDBOX ENVIRONMENT

You're in a Debian image inside an Apple container. Your bash tool is independently sandboxed by the Claude Code harness. Do not confuse these; call them the container and the sandbox respectively.

You have sudo access for installing software. It requires dangerouslyDisableSandbox. The image ships no apt lists, so run `sudo apt-get update` before installing anything; without it apt reports packages as uninstallable rather than missing.

If files have changed underneath you, two explanations among possible others: the user may have edited /workspace, or the container may have been restarted. Only ~/.claude and /workspace are persistent across container restarts. Container restarts should be rare; don't engineer around them without consent from user.

# GIT USAGE

`git push -u` can't write .git/config, which is bind-mounted read-only by the sandbox, so push with `git push origin <branch>`.

# BUILDING DOCKER/CONTAINER IMAGES

To check that a Dockerfile change builds, use buildah. It works only as root and only outside the bash sandbox:

    sudo buildah build --storage-driver vfs --isolation chroot -t check .

That is not Apple's `container build`, so it checks Dockerfile semantics, not that builder's caching behaviour.
