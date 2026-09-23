import sys, types, importlib.util
src = open("/workspace/bin/devbox").read().replace(
    'if __name__ == "__main__":\n    sys.exit(main())', '')
m = types.ModuleType("devbox"); m.__dict__["__name__"] = "devbox"
exec(compile(src, "devbox", "exec"), m.__dict__)

HOME = "/Users/marntzenius"
# The real macOS default shape, in order.
RULES = [("deny", "/Users"), ("allow", HOME),
         ("deny", "/Volumes"), ("deny", "/private/var/db/dslocal"),
         ("deny", f"{HOME}/.ssh"), ("deny", f"{HOME}/.aws"),
         ("deny", f"{HOME}/Library"),
         ("allow", f"{HOME}/Library/Caches"),
         ("deny", f"{HOME}/Library/Caches/Google"),
         ("deny", f"{HOME}/.config/devbox")]
m.default_read_rules = lambda: RULES
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
    ("/Users/someoneelse/x",             True,  "another user's home"),
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
