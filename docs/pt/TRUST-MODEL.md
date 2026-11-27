> **Languages:** [English](../TRUST-MODEL.md) · [العربية](../ar/TRUST-MODEL.md) · [Čeština](../cs/TRUST-MODEL.md) · [Deutsch](../de/TRUST-MODEL.md) · [Español](../es/TRUST-MODEL.md) · [فارسی](../fa/TRUST-MODEL.md) · [Français](../fr/TRUST-MODEL.md) · [हिन्दी](../hi/TRUST-MODEL.md) · [Bahasa Indonesia](../id/TRUST-MODEL.md) · [Italiano](../it/TRUST-MODEL.md) · [日本語](../ja/TRUST-MODEL.md) · [한국어](../ko/TRUST-MODEL.md) · [Nederlands](../nl/TRUST-MODEL.md) · [Polski](../pl/TRUST-MODEL.md) · Português · [Русский](../ru/TRUST-MODEL.md) · [Svenska](../sv/TRUST-MODEL.md) · [ไทย](../th/TRUST-MODEL.md) · [Türkçe](../tr/TRUST-MODEL.md) · [Українська](../uk/TRUST-MODEL.md) · [Tiếng Việt](../vi/TRUST-MODEL.md) · [中文](../zh/TRUST-MODEL.md)

---

# Política de segurança e modelo de confiança

O VDLiveUpdate (VDLU) aplica **atualizações root flashless** a um módulo vivo: escreve
em `/data/adb/modules/<mod>` e troca uma `.so` Zygisk no boot. Todo campo de um manifesto
buscado (`path`, `sha256`, `delete[]`, `mode`, ...) é **input hostil** - uma fonte
envenenada ou um MITM o entrega. Esta página é o modelo de confiança e a política de
divulgação responsável. Para o contrato de costura completo veja [`INTERFACES.md`](INTERFACES.md),
e os internos do engine/producer em [`ENGINE.md`](ENGINE.md) e
[`PRODUCER.md`](PRODUCER.md), a página de wiki **Security-and-Trust-Model** carrega o
mesmo modelo para leitores fora do repo.

## Versões suportadas

Correções de segurança entram no `ENGINE_VERSION` mais recente, um manifesto assinado
declara o engine mínimo de que precisa via `engine_min`, e o engine on-device recusa um
manifesto que peça mais do que ele implementa. Espera-se que engines vendorizados mais
antigos sejam **re-vendorizados** para pegar uma correção, não corrigidos no lugar.

| ENGINE_VERSION | status |
|---|---|
| 7 (atual) | suportado - nunca reverter um módulo à frente do feed (o `versionCode` instalado ao vivo serve de piso para a versão "from"), auto-reparo no boot de um plano de downgrade obsoleto |
| 6 | substituído - auto-reparo no boot de um journal obsoleto com `target <= 0` (o baseline 0 deixado por um stub removido não aciona mais nenhuma UI ou ação de boot) |
| 5 | substituído - exclusão da âncora de confiança no engine (o dir `vdlu/` é ignorado mesmo se um feed o carrega), tetos de 128 MiB por arquivo / 2 MiB de manifesto |
| 4 | substituído - allowlist de `key_id`, rejeição de path com dot-segment/barra-final, limites de tamanho, trava em tempo de check |
| <= 3 | não suportado - re-vendorize o engine atual |

Qualquer mudança na verificação do engine ou na lógica de apply incrementa o `ENGINE_VERSION`.

## Reportando uma vulnerabilidade

Reporte em privado. **Não** abra uma issue pública, PR ou post de fórum para um bug de
segurança. Use os contatos do projeto (veja [`CONTRIBUTING.md`](../CONTRIBUTING.md)):

- Telegram: **@VD_Priv8** (https://t.me/VD_Priv8)
- Canal: **@Priv8_VD** (https://t.me/Priv8_VD)
- E-mail: **vd.priv8@pm.me**

Por favor inclua a versão do engine, o `profile` em uso, e um manifesto ou feed que
reproduza o problema. Correções são entregues como um novo `ENGINE_VERSION` com uma
entrada no `CHANGELOG.md`, coordene o timing da divulgação na thread do report.

## Modelo de confiança

- **Assinaturas ed25519 destacadas.** O producer assina o manifesto canônico no PC
  (openssl), o device verifica com o `ed25519-mini` embarcado - **sem openssl no
  device**. A mensagem assinada é o hex sha256 do manifesto sem seu campo `sig` (chaves
  ordenadas, compacto, UTF-8), então sign e verify derivam os mesmos bytes em dois
  runtimes sem uma biblioteca JSON no device.
- **Keyring = pubkeys RAW de 32 bytes**, só-flash. O keyring do device entrega `<key_id>.pub`
  como a chave RAW de 32 bytes (nunca o PEM), `vdlu-pack` **exclui** o keyring e os
  binários `verify/` do feed, então um manifesto nunca pode reescrever a âncora de
  confiança on-device pela rede.
- **Exclusão da âncora de confiança no engine (VDLU#2).** Independentemente da exclusão no
  lado do producer acima, o engine on-device **ignora** todo path `vdlu/` (`update.sh`,
  `vdlu-verify`, `verify/*`, `keyring/*`, config) em um plano buscado - ele nunca busca, aplica
  ou deleta esses paths, mesmo se um feed os carrega. Um feed publicado entrega a árvore inteira
  do módulo, `vdlu/` incluído, então o engine silenciosamente descarta esses paths em vez de
  rejeitar o manifesto: o módulo ainda atualiza, e a âncora de confiança muda apenas por um
  re-flash assinado completo. Uma única chave de assinatura vazada não pode mais trocar o
  verificador ou a chave de assinatura pela rede e persistir root.
- **Allowlist de `key_id` de module-update (fail-closed, antes da seleção da pubkey).** Um
  keyring pode legitimamente carregar mais de uma chave (por exemplo, uma chave de
  fingerprint-feed de menor confiança ao lado da chave de release). Antes de `<key_id>.pub`
  ser sequer selecionado, `verify_manifest` rejeita qualquer manifesto cujo `key_id` não
  esteja na allowlist configurada, em **ambos** os profiles, e espelha o conjunto resolvido
  para o `vdlu-verify` via `VDLU_KEYID_ALLOW`. Isso fecha um bypass onde uma chave vazada de
  menor confiança poderia de outra forma assinar uma atualização root flashless completa.
  Seguro por padrão quando `key_id` não está definido: um keyring de **chave única**
  auto-fixa naquela única chave, um keyring **multi-chave** é rejeitado até `key_id` ser
  fixado (separado por vírgula para rotação).
- **A raiz de confiança do fingerprint-feed é um path separado e fixado** com sua própria
  chave, nunca é alcançável pelo path de module-update acima.
- **A baseline é uma semente local confiável.** `baseline.json` chega dentro do zip
  flasheado - a fronteira de confiança da instalação - então é não-assinada e sem chave e
  **não** passa pelo `vdlu-verify`, só um manifesto **buscado** do feed é verificado. Isso
  mantém a chave de assinatura fora do CI.

## Garantias fail-closed

- **`validate_plan` roda antes de qualquer fetch ou apply.** No `do_diff`, fail-closed, ele
  rejeita o manifesto **inteiro** se qualquer `path` for absoluto, contiver um segmento `..`
  ou `.`, terminar em `/`, ou tiver um caractere de controle, se qualquer `sha256` não for
  `^[0-9a-f]{64}$`, ou se qualquer `mode`/`class`/`enc` for inválido. Nenhum campo hostil
  alcança um shell, e `cmd_check` não carrega interpolação `system()`.
- **Contenção de path.** Toda escrita e deleção é confinada ao `MODULE_DIR` via
  `contained()` - apply, delete, e o `stage_file` do reboot todos passam pela mesma guarda.
  Symlinks na árvore são pulados pelo producer (nunca vazam conteúdo de fora dela).
- **Dois profiles, fail-closed por inversão.** `trusted` (privado, fonte staged via SSH) é o
  **único** opt-in para verify best-effort, **qualquer** outro valor - incluindo um typo, um
  espaço/CR final, ou um case diferente - é tratado como `hardened`, onde uma assinatura
  válida é **obrigatória** e uma falha aborta. O `sha256` de todo blob é conferido em ambos
  os profiles.
- **Assinatura + hash antes de qualquer exec de ferramenta.** O `curl` estático buscado roda
  como root, então `install-tool` verifica a assinatura do tools-manifest (ed25519-mini,
  obrigatória em **qualquer** profile) e o hash do curl **antes** de ele ser instalado e
  executado - sig+hash antes do exec fecha o RCE.
- **Transação retomável e pin-safe.** O manifesto em voo é fixado em `target.json`, um crash,
  perda de rede, ou reboot retoma do journal sem re-decidir o plano. Downgrade é bloqueado
  (`version` monotônica), o campo `module` assinado deve ser igual a `MODID`, e `delete[]`
  roda só no `finalize_done` (um `PENDING_REBOOT` não deleta nada). Nada é jamais
  "concluído" sem um re-hash completo, nada é sobrescrito sem um backup `rollback/<v>/`
  antes.

## Hardening (defesa em profundidade)

- **Limites de tamanho.** O manifesto, o tools-manifest, e o path de download `wget`/`head -c`
  sem curl são todos limitados antes de serem lidos (anti-OOM / anti-flood). Um blob falha
  sua fase após 3 tentativas. Os tetos são **128 MiB por arquivo** (`MAX_FILE_BYTES`) e
  **2 MiB para o manifesto** (`MAX_MANIFEST_BYTES`), impostos em `update.sh` e espelhados em
  `vdlu-verify`.
- **Trava em tempo de check.** `check` pega o mkdir-lock antes de reconstruir seu work dir,
  então uma execução concorrente não pode correr contra ele.
- **Contenção do staging.** `stage_file` tem a mesma guarda `contained()` que as primitivas
  de apply vivo, então um path reboot-hard staged também não pode escapar do `MODULE_DIR`.
- **TLS é defesa em profundidade, não a raiz de confiança.** O curl estático usa mbedTLS com
  o trust store do Android (`--capath`, override `ca_path`), a garantia de integridade é a
  assinatura ed25519, a checagem de cert é uma segunda camada.

## Veja também

- [`INTERFACES.md`](INTERFACES.md) - o contrato de costura imutável (§5 config, §6 assinatura, §11 toolchain).
- [`ENGINE.md`](ENGINE.md) - o engine device-side e sua máquina de estados.
- [`PRODUCER.md`](PRODUCER.md) - packing, assinatura, canonicalização, e rotação de chave.
- Wiki: **Security-and-Trust-Model**.

<!-- doc-footer -->

---

> _Esta documentação foi gerada com o Claude (Anthropic) e é mantida por VD171. Correções e melhorias são bem-vindas, veja [CONTRIBUTING.md](CONTRIBUTING.md)._
