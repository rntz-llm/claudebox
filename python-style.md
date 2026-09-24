One line between top level declarations. Exception: when useful, files should be separated
into sections, separated by two empty lines and an eye-catching header comment, eg:

```
def bar(): ...


# -------------------- OTHER SECTION --------------------
def baz(): ...

def quux(): ...


# -------------------- SECTION NAME IN ALL CAPS --------------------
# more explanation/documentation for section goes here if necessary.
# if there IS explanation here, add an empty line below it.

def xyzzy(): ...
```

As a rule of thumb, define callees before callers: if `bar` calls `foo`, put `def foo`
before `def bar`. If a function is called in only a few places, keep it close to its
callers. If it's called only once, consider inlining it.
