# Reboot Handling

The whole point of VDLU is to update a module without re-flashing it, and, wherever possible, without rebooting at all. Most files in a module can be replaced while the device is running. A few genuinely cannot, because the kernel or the zygote process has already mapped them and will not notice a change until the next boot.

VDLU's job is to tell those two groups apart automatically, apply everything it safely can **live**, and defer only the genuinely boot-bound files to a reboot that it clearly flags. This page explains how.

For the engine mechanics underneath this, see [[Engine]]. For the big picture, see [[Architecture]].

## Why not just reboot every time

A reboot is the most expensive thing an update can ask of someone. It interrupts whatever they are doing, it takes a minute or more, and it trains people to dread updates. A good incremental updater should feel invisible: you tap update, a few files change under the running system, and you are already on the new version.

So VDLU inverts the usual assumption. The default is live. A file is deferred to a reboot only when it is provably one of the kernel- or zygote-bound kinds, and even then only that file waits. Everything around it still updates immediately.

## The three classes

Every file in the feed is assigned a class. The producer can set it explicitly in the manifest, but in practice the class is derived from the path, and the engine will only ever upgrade a file toward `reboot`, never downgrade it toward `live`. The classes are:

**LIVE** is the common case: web UI assets, binaries, scripts that are read on demand, config files, `module.prop`, and anything else not matched by the rules below. A live file is backed up and then atomically renamed over the target while the system runs. No reboot, and the change is in effect the moment the rename lands.

**SOFT** is the module's own lifecycle scripts: `service.sh`, `post-fs-data.sh`, and `boot-completed.sh`. These are applied live exactly like LIVE files, so the new copy is already on disk. The reason they get their own class is that the running system has already executed the old copy this boot; the new one simply runs next boot, with no staging and no banner. There is nothing to defer, just a natural handover.

**REBOOT-hard** is the small set that cannot change under a running system:

- native libraries, `*.so` (anything under a `zygisk/` path), because zygote maps them into every app at startup;
- `/system` overlay files, because the overlay is mounted at boot;
- `sepolicy.rule` files, because SELinux policy is loaded early.

A REBOOT-hard file is never written over its live inode while the system is up. Overwriting a `.so` that zygote has already mapped is how you get crashes and inconsistent state. Instead the new content is **staged** next to the state directory and swapped in at the next boot, before anything can map it.

## Path to class, at a glance

The engine derives the class from the path like this:

| Path pattern | Class | Applied |
|---|---|---|
| `zygisk/**`, `**/zygisk/**` (the `.so` files) | REBOOT-hard | staged, swapped pre-zygote at boot |
| `system/**` (overlay) | REBOOT-hard | staged, swapped at boot |
| `*.rule` (sepolicy) | REBOOT-hard | staged, swapped at boot |
| `service.sh`, `post-fs-data.sh`, `boot-completed.sh` | SOFT | written live, runs next boot |
| `webroot/**`, `bin/**`, `lib/**`, configs, `module.prop`, everything else | LIVE | written live, effective immediately |

The manifest may carry an explicit `class` per file, but the derived class acts as a floor: if a file looks REBOOT-hard by its path, it is treated as REBOOT-hard even if the manifest says otherwise. This keeps a mislabeled feed from ever trying to hot-swap a `.so`.

## How a run handles both groups at once

During a normal `run` (the DIFF to FETCH to APPLY to COMMIT cycle described in [[Engine]]), the two groups are handled in the same transaction:

```
run:
  LIVE + SOFT  --> backup -> write .vdlu-tmp -> verify -> atomic rename   (effective now)
  REBOOT-hard  --> materialize into staged/<path>.vdlu-new                (live inode untouched)

  re-hash every LIVE + SOFT file
       |
       +-- nothing staged  --> DONE
       +-- something staged --> PENDING_REBOOT  (reboot banner in the WebUI)
```

So after a run that touched a `.so`, you are already on the new version for every live file, and only the staged pieces are waiting. The journal reports `reboot_pending`, and the WebUI shows a persistent banner inviting a reboot to activate the staged files. There is no bogus "done": a run with staged files finishes in `PENDING_REBOOT`, not `DONE`.

## The swap at boot

The staged files are applied by the `boot` command, which the host module wires into `post-fs-data.sh` so it runs synchronously and **pre-zygote**, before any process can map the new `.so`.

`boot` does a `resume` (to finish any interrupted phase) and then the swap. For each staged REBOOT-hard file it:

1. confirms the staged path stays inside the module directory (a containment check);
2. re-hashes `staged/<path>.vdlu-new` against the manifest hash;
3. backs up the current live file;
4. `mv -f` the staged file over the live one and `chmod`s it;
5. re-hashes the file now in place, to confirm the swap landed correctly;
6. marks it applied.

Only once every staged file has swapped and re-verified does the transaction close from `PENDING_REBOOT` to `DONE`. If any step fails, the journal records the error and the module keeps its previous files; nothing is left half-swapped.

Because the swap is a sequence of re-hashes and atomic renames, running `boot` is safe even if it was interrupted last time. It simply picks the staged files back up.

## auto_on_reboot

Staging is only half of a reboot-free feel; the other half is that the user should never have to remember to run the swap. With `auto_on_reboot=1` in the config, the host module's `post-fs-data.sh` calls `update.sh boot` on every boot. That means:

- if a transaction is pending reboot, the staged files are swapped in automatically before zygote starts, and the user just finds themselves fully on the new version;
- if there is nothing pending, `boot` can run a fresh cycle and apply everything, including a `.so`, in that single boot, since it is already running pre-zygote.

In other words, a staged `.so` costs the user nothing beyond a reboot they were going to do anyway. They do not have to tap anything the second time.

## Offline at boot, without draining the battery

Sometimes `boot` wants to check the feed but the device has no network yet. VDLU can wait for it, patiently and cheaply, controlled by `boot_retry_minutes` (0 turns it off). The waiting is deliberately battery-safe:

- between attempts it simply `sleep`s, which freezes in deep sleep, so the device sleeps normally and the retry resumes only once the device is already awake;
- it holds no wakelock and does not hold the engine lock while waiting, so a manual run is never blocked;
- before each attempt it checks whether the network is allowed with a kernel route lookup that sends no packet and does not wake the radio;
- it never retries a deterministic failure such as a bad signature or a blocked downgrade, only a genuine network-absent condition.

The manifest check itself stays free on any network, so you always learn an update exists; only the download waits for the network policy to be satisfied, deferring cleanly rather than erroring.

## See also

- [[Engine]]: the transaction, the apply-by-class logic, and the `boot` command in full.
- [[Architecture]]: where the engine sits among the producer and WebUI.
