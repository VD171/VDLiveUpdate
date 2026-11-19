# Contributing to VDLiveUpdate

VDLU is a flashless, incremental self-update engine vendored into KernelSU/APatch/Magisk modules.
Contributions are welcome.

- Read [INTERFACES.md](INTERFACES.md) first: it is the seam contract between the components (the law of
  convergence). Treat it as immutable unless a change is coordinated across the engine, producer and WebUI.
- Test end to end before a PR: `producer/vdlu-keygen`, `vdlu-pack`, `vdlu-sign`, then the engine
  (`check` / `run` / `boot`). Also `sh -n engine/*.sh` and `node --check webui/vdlu.js`.
- Security is non-negotiable: every manifest field is hostile input and `validate_plan()` stays
  fail-closed; the private signing key never touches CI or a device.
- POSIX sh on the device (no bashisms beyond `local`, no `jq`); keep comments terse.
- One logical change per PR; say what changed and why.

## Contacts

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- Channel: @Priv8_VD https://t.me/Priv8_VD
- E-mail: vd.priv8@pm.me

<!-- doc-footer -->

---

> _This documentation was generated with Claude (Anthropic) and is maintained by VD171. Corrections and improvements are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md)._
