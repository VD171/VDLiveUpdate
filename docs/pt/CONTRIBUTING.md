> **Languages:** [English](../../CONTRIBUTING.md) · [العربية](../ar/CONTRIBUTING.md) · [Čeština](../cs/CONTRIBUTING.md) · [Deutsch](../de/CONTRIBUTING.md) · [Español](../es/CONTRIBUTING.md) · [فارسی](../fa/CONTRIBUTING.md) · [Français](../fr/CONTRIBUTING.md) · [हिन्दी](../hi/CONTRIBUTING.md) · [Bahasa Indonesia](../id/CONTRIBUTING.md) · [Italiano](../it/CONTRIBUTING.md) · [日本語](../ja/CONTRIBUTING.md) · [한국어](../ko/CONTRIBUTING.md) · [Nederlands](../nl/CONTRIBUTING.md) · [Polski](../pl/CONTRIBUTING.md) · Português · [Русский](../ru/CONTRIBUTING.md) · [Svenska](../sv/CONTRIBUTING.md) · [ไทย](../th/CONTRIBUTING.md) · [Türkçe](../tr/CONTRIBUTING.md) · [Українська](../uk/CONTRIBUTING.md) · [Tiếng Việt](../vi/CONTRIBUTING.md) · [中文](../zh/CONTRIBUTING.md)

---

# Contribuindo para o VDLiveUpdate

O VDLU é um engine de auto-atualização flashless e incremental vendorizado em módulos KernelSU/APatch/Magisk.
Contribuições são bem-vindas.

- Leia [INTERFACES.md](INTERFACES.md) primeiro: é o contrato de costura entre os componentes (a lei da
  convergência). Trate-o como imutável a menos que uma mudança seja coordenada entre o engine, o producer e a WebUI.
- Teste ponta a ponta antes de um PR: `producer/vdlu-keygen`, `vdlu-pack`, `vdlu-sign`, depois o engine
  (`check` / `run` / `boot`). Também `sh -n engine/*.sh` e `node --check webui/vdlu.js`.
- Segurança é inegociável: todo campo do manifesto é input hostil e `validate_plan()` permanece
  fail-closed; a chave de assinatura privada nunca toca o CI nem um device.
- sh POSIX no device (sem bashismos além de `local`, sem `jq`); mantenha os comentários concisos.
- Uma mudança lógica por PR; diga o que mudou e por quê.

## Contatos

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- Canal: @Priv8_VD https://t.me/Priv8_VD
- E-mail: vd.priv8@pm.me

<!-- doc-footer -->

---

> _Esta documentação foi gerada com o Claude (Anthropic) e é mantida por VD171. Correções e melhorias são bem-vindas; veja [CONTRIBUTING.md](CONTRIBUTING.md)._
