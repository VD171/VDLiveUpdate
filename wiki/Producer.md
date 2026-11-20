# Producer

The **producer** is the PC / release side of VDLU: the small set of tools that turn a finished module tree into a signed, content-addressed feed the device can update from. Nothing here runs on the phone. These tools run on your release machine (or, for the parts that are safe to, in CI).

There are four of them:

| Tool | Runs on | Language | Job |
|---|---|---|---|
| `vdlu-pack` | PC / CI | python3 | Walk the final module tree into `manifest.json` + `blobs/<sha256>` |
| `vdlu-keygen` | PC | sh + openssl | Generate an ed25519 signing keypair |
| `vdlu-sign` | PC | sh + openssl | Inject `key_id` + signature into a manifest, in place |
| `vdlu-gc` | PC | python3 | Prune orphan blobs from a published feed (fail-safe) |

The release flow is three steps, done once per release: **pack, then sign, then publish**. `vdlu-keygen` is a one-time setup, and `vdlu-gc` is housekeeping you run when the feed grows. Everything the producer emits conforms to the [[Feed Format]], which is what the engine on the device consumes.

---

## vdlu-pack

`vdlu-pack` takes the **exact tree your `.zip` ships** (the final tree, after your build has applied its own whitelist and ABI pruning) and produces the feed for it.

```sh
vdlu-pack <module_tree_dir> <out_dir> <module_id> <version> \
          [--version-name v106] [--channel stable] [--prev ./prev/manifest.json]
```

It writes two things into `<out_dir>`:

- `manifest.json` - the complete description of the target tree (every file with its `sha256`, `size`, `mode`, encoding and reboot class), still **unsigned** (the `key_id` and `sig` fields are empty placeholders).
- `blobs/<sha256>` (or `blobs/<sha256>.gz`) - one blob per distinct file content.

### Content-addressed and deduplicating

Every blob is named by the **sha256 of its original (uncompressed) content**. Because the name is the hash, identical content lands on the same blob. `vdlu-pack` writes a blob only if it is not already present, so:

- A file that did not change keeps the same blob name, and is never re-written or re-pushed.
- Two different files with identical content share one blob.
- A reverted file reuses the blob that was already there from before.

Publishing is therefore **incremental by construction**: across releases, `blobs/` only ever grows, and only genuinely new content gets added. The device fetches by the same hashes, so it downloads only the blobs it does not already hold.

### Compression (the `enc` field)

For each file, `vdlu-pack` decides how to store the blob:

- `gz` when the file is at least 4096 bytes **and** gzip (deterministic `-9 -n`) saves at least 10 percent.
- `raw` otherwise (small files that on-the-wire gzip already covers, or already-incompressible data).
- If `gzip` is missing on the build host, everything is stored `raw`. Packing never fails over this.

The `sha256` in the manifest is **always** of the original content; `enc` only names how the blob happens to be stored. The device decompresses `gz` blobs with toybox `gunzip` and then checks the hash against the original.

### Reboot class and safety

`vdlu-pack` also tags each file with a reboot `class` (`live`, `soft`, `reboot`) derived from its path, so the engine knows what can be applied without a reboot and what must be staged. The rules and what the device does with each class are covered in [[Reboot Handling]].

A few things `vdlu-pack` deliberately does **not** do:

- It does not follow symlinks (it skips them with a warning, so content from outside the tree, like a link to a system file, can never leak into a blob).
- It skips non-regular files (directories, fifos, devices).
- It honors `SOURCE_DATE_EPOCH` for the `built` timestamp, so manifests are reproducible.
- It excludes a fixed set of paths from the feed entirely (the trust root, installer scaffolding, and a few others). The full list, and why each one is excluded, is in [[Feed Format]].

### The `delete[]` list

Pass `--prev <previous manifest.json>` and `vdlu-pack` computes `delete[]`: the paths that existed in the previous release but are gone in this one, so the device removes them instead of leaving orphans behind. Excluded paths are never emitted as deletes, even when they appear in the previous manifest (see [[Feed Format]] for the exact semantics).

---

## vdlu-keygen

A one-time step. `vdlu-keygen` creates the ed25519 signing keypair for your feed.

```sh
vdlu-keygen <id> <out_dir>
```

It writes three files:

| File | What it is | Where it goes |
|---|---|---|
| `<id>.pem` | The **private** signing key (mode `0600`) | Stays on your release machine. Never. |
| `<id>.pub` | The public key as PEM | PC-side tooling only |
| `<id>.pub.raw` | The public key as **raw 32 bytes** | Shipped as the module's on-device keyring entry |

The raw 32-byte public key is what the device verifier reads (it carries no `openssl`, so it cannot read the PEM). You embed `<id>.pub.raw` into the module as `vdlu/keyring/<id>.pub`. The PEM is for PC-side use only. This split, and how key rotation works, is explained in [[Security and Trust Model]].

> The private `.pem` is the one secret in the whole system. Keep it off every device and out of every repository push. See the CI note below.

---

## vdlu-sign

`vdlu-sign` takes the unsigned manifest `vdlu-pack` produced and signs it **in place**.

```sh
vdlu-sign <manifest.json> <privkey.pem> <key_id>
```

It sets the `key_id` field, computes the canonical form of the manifest, and writes the ed25519 signature (base64) into the `sig` field. The signature is over a precise byte transform of the manifest so that the PC and the device derive exactly the same signed bytes with no JSON library on the device. That transform (the **canonicalization**) is the single most important invariant in the format, and it is documented in full in [[Feed Format]].

The private key is read only here, on your machine, and never leaves it.

### The signing key stays off CI

This is a deliberate design point. CI can run `vdlu-pack` and produce a perfectly valid **keyless baseline** (an unsigned seed manifest; see [[Feed Format]]), so a fresh install is born current without CI ever touching a private key. The actual signing of the published feed is done by you, locally, with `vdlu-sign`. That way the signing key is 100 percent out of CI, and only the feed you publish by hand is signed.

---

## vdlu-gc

Because blobs are content-addressed and immutable, `blobs/` only ever grows: `vdlu-pack` adds, it never removes. Over many releases the feed (and the Pages site hosting it) accumulates blobs that no current manifest references anymore. `vdlu-gc` prunes those orphans.

```sh
vdlu-gc <feed_dir> [--keep-last N] [--keep extra.json ...] [--apply]
```

It builds the **retained set** of manifests: the current `manifest.json`, plus the last `N` archived manifests by version (default `N=3`, giving a rollback margin), plus any you name with `--keep`. A blob referenced by **no** retained manifest is an orphan and is a candidate for removal. The retained set is a union, so a blob stays as long as any retained release still needs it; a device sitting on an older retained version never loses its fetch.

`vdlu-gc` is built to be safe:

- **Dry-run by default.** With no `--apply`, it only prints what it *would* remove. You add `--apply` to actually delete.
- **Fail-safe.** If it finds no retained manifest at all, it refuses to prune rather than risk emptying a feed.
- **Retention by reference, not by date.** A blob is kept because a retained manifest points at it, never because of a timestamp.

After pruning, push the smaller feed to your host. Space the write out if your host rate-limits batched writes.

---

## Putting it together

A typical release, end to end:

```sh
# one-time: make a signing key. Keep the .pem off every device and every repo push.
vdlu-keygen release-2026 ./keys

# each release: pack the final shipped tree (post-whitelist, same tree the .zip ships)
vdlu-pack ./module_tree ./out demo 106 --version-name v106 --channel stable \
          --prev ./prev/manifest.json

# sign the manifest in place (local, private key never leaves your machine)
vdlu-sign ./out/manifest.json ./keys/release-2026.pem release-2026

# publish ./out/{manifest.json,blobs/} to your source (GitHub Pages, rsync, ...).
# occasionally: prune orphan blobs
vdlu-gc ./feed --keep-last 3            # dry-run first
vdlu-gc ./feed --keep-last 3 --apply    # then delete
```

For the full worked example of adopting VDLU into a module, see [[Quick Start]]. For the on-wire shape of everything the producer emits, see [[Feed Format]]. For the reasoning behind the key handling and what is kept out of the feed, see [[Security and Trust Model]].
