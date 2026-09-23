One line between top level declarations. Exception: when useful, files should be separated into sections, separated by two empty lines and an eye-catching header comment, eg:

```
def bar(): ...


# -------------------- OTHER SECTION --------------------
def bar(): ...

def quux(): ...


# -------------------- SECTION NAME IN ALL CAPS --------------------
# more explanation/documentation for section goes here if necessary.
# if there IS explanation here, add an empty line below it.

def xyzzy(): ...
```
