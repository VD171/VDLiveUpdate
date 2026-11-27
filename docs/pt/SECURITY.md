> **Languages:** [English](../../SECURITY.md) · [العربية](../ar/SECURITY.md) · [Čeština](../cs/SECURITY.md) · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · [فارسی](../fa/SECURITY.md) · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · [Italiano](../it/SECURITY.md) · [日本語](../ja/SECURITY.md) · [한국어](../ko/SECURITY.md) · [Nederlands](../nl/SECURITY.md) · [Polski](../pl/SECURITY.md) · Português · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · [中文](../zh/SECURITY.md)

---

# Política de Segurança

VDLiveUpdate (VDLU) aplica atualizações flashless com root a um módulo vivo: ele grava
no diretório do próprio módulo e troca uma `.so` Zygisk no boot, rodando no contexto
root do módulo. Levamos segurança a sério.

## Reportando uma vulnerabilidade

- **Site:** https://vd171.ru
- **Site:** https://vd.priv8.ru
- **Issues:** https://github.com/VD171/VDLiveUpdate/issues
- **GitHub:** [@VD171](https://github.com/VD171)
- **XDA-Developers:** [@VD171](https://xdaforums.com/m/vd171.4699873/)
- **Telegram:** [@VD_Priv8](https://t.me/VD_Priv8)
- **Channel:** [@Priv8_VD](https://t.me/Priv8_VD)
- **Discord:** [@VD.Priv8](https://discord.com/users/1296831918989639721)
- **E-mail:** vd.priv8@pm.me

Inclua uma descrição clara e, se possível, um manifesto ou feed que reproduza o
problema. Responderemos assim que pudermos e daremos crédito a você se desejar.

## Notas de escopo

- As atualizações são blobs content-addressed mais um `manifest.json` assinado com
  ed25519. O dispositivo verifica a assinatura com um `ed25519-mini` embarcado (sem
  openssl no dispositivo), e todo blob é conferido contra o seu `sha256` antes de ser
  usado.
- O perfil hardened (o padrão público) exige uma assinatura válida e bloqueia downgrade.
  A versão "de origem" tem como piso o `versionCode` do módulo instalado (lido de
  `module.prop`), então um módulo nunca é revertido para trás do feed.
- A raiz de confiança (a chave pública ed25519 raw do `keyring/` e os binários de
  `verify/`) é somente-flash e nunca é rotacionada pela rede. O produtor a exclui do feed
  e o engine ignora todo caminho `vdlu/` em um plano baixado, então uma chave de
  assinatura vazada não pode trocar o verificador ou a chave e persistir root.
- Um manifesto validamente assinado para outro módulo não pode gravar no diretório de um
  módulo diferente. O campo `module` assinado precisa ser igual ao `MODID` do dispositivo
  (verificação de vínculo entre módulos), e toda gravação e exclusão fica confinada ao
  diretório do módulo.
- O engine roda no contexto root do próprio módulo e nunca o enfraquece. Ele não adiciona
  privilégio e não interpola nenhum campo do manifesto em um shell, todo valor de `path`,
  `sha256`, `mode` e `delete[]` é validado como entrada hostil antes do uso.
- A postura é fail-closed. Um valor de `profile` corrompido ou desconhecido nunca escorrega
  para aceitar conteúdo não assinado (qualquer coisa que não seja exatamente `trusted` é
  tratada como `hardened`), e um backup é gravado antes de qualquer arquivo ser
  sobrescrito, então um apply que falhe nunca destrói a versão instalada.
- Veja [TRUST-MODEL.md](TRUST-MODEL.md) para o modelo de confiança completo, as garantias
  fail-closed e os detalhes de hardening.

<!-- doc-footer -->

---

> _Esta documentação foi gerada com o Claude (Anthropic) e é mantida por VD171. Correções e melhorias são bem-vindas, veja [CONTRIBUTING.md](CONTRIBUTING.md)._
