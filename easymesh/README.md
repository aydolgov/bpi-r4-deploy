apk v3 repository for the EasyMesh R6 stack.

Served from GitHub Pages rather than release assets on purpose: a release asset
name cannot contain a tilde - GitHub silently rewrites it to a dot - and six of
these packages carry one in their version (`2026.02.19~53d12cd4-r2`). apk builds
the download URL from the version in the index, asks for the tilde, and gets a
404. Measured 2026-08-13 on a freshly flashed board: two packages failed with
"wget: exited with error 8" and the install ended with 2 errors.

Pages serves real paths, so the filenames stay exactly as the index describes.


## This feed is a lab tool, not a product path

Install from it with `--allow-untrusted`, on **both** commands:

```sh
apk update --allow-untrusted && apk add --allow-untrusted easymesh
```

The index is not signed, and will not be. Signing it once, on 2026-08-14, did
work - apk accepted it with no flags at all, and so did LuCI's package manager,
which never passes `--allow-untrusted` and therefore cannot install from an
unsigned feed at all. But the key that made it work is generated *inside* the
build tree, and every builder starts with `rm -rf openwrt`: the x8 tree
regenerated its own at 11:09 that morning, so the two trees already disagreed
about which key was real. A signature that stops verifying after the next build
is worse than none, because it looks like a fault in the feed rather than a
key that no longer exists.

So: no signature, `--allow-untrusted` in the lab, and nothing here reaches a
user. Users get a production image with the whole stack baked in - no feed, no
repository line, no package manager. Flash, then the wizard.
