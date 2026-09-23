#!/usr/bin/env python3
"""Pins refuse_denied_cwd()'s rule evaluation.

The rules are last-match-wins, and getting that wrong once made devbox refuse
to run anywhere under $HOME: every path there matches the `/Users` deny that
the `$HOME` allow immediately overrides. The fixture below is the real macOS
shape, which the usual $TMPDIR-based fixtures can't reproduce -- a fake $HOME
outside /Users leaves every /Users rule inert.
"""

import contextlib
import importlib.machinery
import importlib.util
import io
import os
import sys

DEVBOX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bin", "devbox")

def load(path):
    """Import bin/devbox as a module. It has no .py extension, hence the
    explicit loader; the module name is not "__main__", so main() stays put."""
    loader = importlib.machinery.SourceFileLoader("devbox", path)
    spec = importlib.util.spec_from_file_location("devbox", path, loader=loader)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

HOME = "/Users/someone"

def fixture_directives(cwd):
    """The built-in policy's shape: cwd allowed early, ahead of the credential
    denies, so those override it."""
    return [("deny", "read", "/Users"),
            ("allow", "read", HOME),
            ("allow", "write", cwd),
            ("allow", "write", "/tmp"),
            ("deny", "read", "/Volumes"),
            ("deny", "read", "/private/var/db/dslocal"),
            ("deny", "read", f"{HOME}/.ssh"),
            ("deny", "read", f"{HOME}/.aws"),
            ("deny", "read", f"{HOME}/Library"),
            ("allow", "read", f"{HOME}/Library/Caches"),
            ("deny", "read", f"{HOME}/Library/Caches/Google"),
            ("deny", "read", f"{HOME}/.config/devbox")]

CASES = [
    (f"{HOME}/t/wub",                   False, "ordinary project dir"),
    (f"{HOME}/src/repo",                False, "ordinary project dir"),
    (f"{HOME}/.ssh",                    True,  "the denied dir itself"),
    (f"{HOME}/.ssh/sub",                True,  "under a denied dir"),
    (f"{HOME}/.aws/x",                  True,  "under a denied dir"),
    (f"{HOME}/Library/Preferences",     True,  "under ~/Library"),
    (f"{HOME}/Library/Caches/proj",     False, "re-allowed under ~/Library"),
    (f"{HOME}/Library/Caches/Google/x", True,  "re-denied under Caches"),
    # cwd is allowed ahead of the credential denies, so it punches through the
    # /Users deny -- the same mechanism that makes /Users/Shared work. POSIX
    # still gates access, and refuse_unreasonable_cwd() still refuses to
    # target a whole home directory.
    ("/Users/Shared/project",           False, "shared, outside $HOME"),
    ("/Users/someoneelse/x",            False, "deliberately chosen as cwd"),
    ("/Volumes/Backup/repo",            True,  "a mounted volume"),
    ("/opt/work/repo",                  False, "outside /Users entirely"),
]

def main():
    devbox = load(DEVBOX)
    devbox.default_directives = fixture_directives
    devbox.vet = lambda path: path  # already absolute in the fixture

    def refused(cwd):
        with contextlib.redirect_stderr(io.StringIO()):
            try:
                devbox.refuse_denied_cwd(cwd)
                return False
            except SystemExit:
                return True

    bad = 0
    for cwd, want, why in CASES:
        got = refused(cwd)
        bad += got != want
        print(f"  {'ok  ' if got == want else 'FAIL'} "
              f"{'refused' if got else 'allowed':>7}  {cwd:<38} ({why})")
    print(f"\n{len(CASES)} cases, {bad} wrong")
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
