Some tools for setting up an Apple container to sandbox Claude in a lightweight VM while giving it network access and the ability to install tools it needs.

`bin/devbox` is the lighter-weight sibling: instead of a VM, it runs a command
against the current directory under a macOS `sandbox-exec` profile that permits
writes only inside that directory, denies reads of the rest of your home
directory, and denies the network unless you ask for it. See DEVBOX.md.
