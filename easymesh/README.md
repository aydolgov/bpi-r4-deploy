apk v3 repository for the EasyMesh R6 stack.

Served from GitHub Pages rather than release assets on purpose: a release asset
name cannot contain a tilde - GitHub silently rewrites it to a dot - and six of
these packages carry one in their version (`2026.02.19~53d12cd4-r2`). apk builds
the download URL from the version in the index, asks for the tilde, and gets a
404. Measured 2026-08-13 on a freshly flashed board: two packages failed with
"wget: exited with error 8" and the install ended with 2 errors.

Pages serves real paths, so the filenames stay exactly as the index describes.
