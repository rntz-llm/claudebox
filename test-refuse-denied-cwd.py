import sys, types, importlib.util
src = open("/workspace/bin/devbox").read().replace(
    'if __name__ == "__main__":\n    sys.exit(main())', '')
m = types.ModuleType("devbox"); m.__dict__["__name__"] = "devbox"
exec(compile(src, "devbox", "exec"), m.__dict__)

HOME = "/Users/marntzenius"
# The real macOS default shape, in order. cwd is allowed early, ahead of the
# credential denies, so those override it.
def directives(cwd):
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
m.default_directives = directives
m.vet = lambda path: path          # already absolute in the fixture
def refused(cwd):
    try:
        m.refuse_denied_cwd(cwd); return False
    except SystemExit:
        return True

cases = [
    (f"{HOME}/t/wub",                    False, "ordinary project dir"),
    (f"{HOME}/src/repo",                 False, "ordinary project dir"),
    (f"{HOME}/.ssh",                     True,  "the denied dir itself"),
    (f"{HOME}/.ssh/sub",                 True,  "under a denied dir"),
    (f"{HOME}/.aws/x",                   True,  "under a denied dir"),
    (f"{HOME}/Library/Preferences",      True,  "under ~/Library"),
    (f"{HOME}/Library/Caches/proj",      False, "re-allowed under ~/Library"),
    (f"{HOME}/Library/Caches/Google/x",  True,  "re-denied under Caches"),
    # cwd is allowed ahead of the credential denies, so it punches through
    # the /Users deny -- the same mechanism that makes /Users/Shared work.
    # POSIX still gates access, and refuse_unreasonable_cwd() still blocks
    # targeting a whole home directory.
    ("/Users/Shared/project",            False, "shared, outside $HOME"),
    ("/Users/someoneelse/x",             False, "deliberately chosen as cwd"),
    ("/Volumes/Backup/repo",             True,  "a mounted volume"),
    ("/opt/work/repo",                   False, "outside /Users entirely"),
]
bad = 0
for cwd, want, why in cases:
    got = refused(cwd)
    flag = "ok " if got == want else "FAIL"
    if got != want: bad += 1
    print(f"  {flag} {'refused' if got else 'allowed':>8}  {cwd:<34} ({why})")
print(f"\n{len(cases)} cases, {bad} wrong")
sys.exit(1 if bad else 0)
