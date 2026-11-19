# Third-Party Notices

VDLiveUpdate's own code is licensed under Apache-2.0 (see [LICENSE](LICENSE)). It builds on and bundles
the following third-party components, each under its own license.

## TweetNaCl - public domain

The `verify/ed25519-mini` verifier is built from TweetNaCl (`tweetnacl.c` / `tweetnacl.h`) by
Daniel J. Bernstein, Bernard van Gassel, Wesley Janssen, et al., which its authors placed in the
public domain. See https://tweetnacl.cr.yp.to/. Only the thin `main.c` wrapper around it is
VDLiveUpdate's own code (Apache-2.0).

## curl 8.11.1 - curl license

The static `tools/curl/<abi>/curl` TLS fetch helper is an unmodified build of curl 8.11.1
(https://curl.se/), used under the curl license (an MIT/X-derivative). See
https://curl.se/docs/copyright.html.

## Mbed TLS 3.6.7 - Apache-2.0

The bundled curl is statically linked against Mbed TLS 3.6.7
(https://github.com/Mbed-TLS/mbedtls), used under the Apache License 2.0.

## `.github/scripts/gen-doc-nav.py` - AGPL-3.0-or-later

One repository tooling file, `.github/scripts/gen-doc-nav.py` (the shared documentation
nav + footer generator), is licensed under **AGPL-3.0-or-later**, not Apache-2.0. It is a
build-time developer utility and is not shipped to any device or vendored into a module;
the rest of VDLiveUpdate's own code remains Apache-2.0. This entry discloses the split so
the licensing is transparent.

---

Build provenance (sources, versions, SHA-256 of the tarballs and binaries, and the toolchain) is
recorded in `tools/curl/PROVENANCE.json` and `verify/ed25519-mini/PROVENANCE.json`.
