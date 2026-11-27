> **Languages:** [English](../INTERFACES.md) · [العربية](../ar/INTERFACES.md) · [Čeština](../cs/INTERFACES.md) · [Deutsch](../de/INTERFACES.md) · [Español](../es/INTERFACES.md) · [فارسی](../fa/INTERFACES.md) · [Français](../fr/INTERFACES.md) · [हिन्दी](../hi/INTERFACES.md) · [Bahasa Indonesia](../id/INTERFACES.md) · [Italiano](../it/INTERFACES.md) · [日本語](../ja/INTERFACES.md) · [한국어](../ko/INTERFACES.md) · [Nederlands](../nl/INTERFACES.md) · [Polski](../pl/INTERFACES.md) · Português · [Русский](../ru/INTERFACES.md) · [Svenska](../sv/INTERFACES.md) · [ไทย](../th/INTERFACES.md) · [Türkçe](../tr/INTERFACES.md) · [Українська](../uk/INTERFACES.md) · [Tiếng Việt](../vi/INTERFACES.md) · [中文](../zh/INTERFACES.md)

---

# VDLU - Contrato de interface (a costura entre os componentes)

**Lei da convergência:** todo componente se conforma a este arquivo. As peças de 4 agentes precisam **encaixar-se** -
as assinaturas de CLI, nomes de arquivo e chaves JSON abaixo são **imutáveis** (uma mudança significa alinhar aqui
primeiro).

Princípios herdados dos repositórios: **sh POSIX puro** no device (sem bashismos, roda com toybox/busybox +
`sha256sum`/`gzip`/`base64` do toybox + o `curl` buscado + o `ed25519-mini` embarcado - enxuto, sem pacote
de binários), **zero comentário gratuito**, **sempre release**, **rigor na falha** (transação retomável, nada
falsamente "concluído", nada perdido), **nada afrouxado**.

---

## 1. Layout de estado (Tier-2, fora do diretório do módulo)

```
$VDLU_DIR = /data/adb/<module>/vdlu
  config               # key=value (§5)
  current.json         # manifest of the ACTIVE version (diff base); absent = never updated
  journal.json         # transaction in progress (§4); absent = idle
  cancel               # presence = cancel request (WebUI creates it; engine deletes it on stop)
  lock.d/              # mkdir-lock (flock unworkable on toybox; stale-recovery by PID)
  blobs/<sha256>       # cache of verified blobs (ORIGINAL content, already decompressed)
  rollback/<version>/<path>   # backup of overwritten files
  staged/<path>.vdlu-new      # REBOOT-hard awaiting swap at boot
  target.json          # PINNED manifest of the in-flight transaction (presence = active transaction; becomes current.json on DONE)
  plan.tsv  plan.del   # engine's internal plan (progress); the WebUI IGNORES it (reads only journal/config/current)
```
`cancelled:true` no journal = o engine parou num cancelamento (um estado não-terminal, retomável, `error`
permanece null).

Engine vendorizado no módulo: `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`). `$MODULE_DIR =
/data/adb/modules/<module>`. O engine recebe via env: `VDLU_DIR`, `MODULE_DIR`, `MODID`.

## 2. CLI do engine (componente ENGINE)

`sh update.sh <cmd>` - rc 0 = ok, !=0 = erro (stderr traz o motivo):

| cmd | faz |
|---|---|
| `check` | DIFF: baixa o manifesto, compara; imprime um JSON de 1 linha `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; não muda nada. Device À FRENTE do feed (downgrade bloqueado, endurecido) = um estado BENIGNO: `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (nunca "check failed"). rc de do_diff: 2 fetch/parse, 3 verify/meta, 4 ahead |
| `run` | ciclo completo: DIFF→FETCH→APPLY→COMMIT; honra `cancel`; escreve progresso em `journal.json`; aplica LIVE, encena REBOOT-hard |
| `resume` | retoma a transação de `journal.json` a partir da fase atual (idempotente) |
| `boot` | modo pré-zygote: `resume` + faz o SWAP dos `staged/*.vdlu-new` (aplica a `.so`), fecha `PENDING_REBOOT`→`DONE` |
| `status` | imprime `journal.json` (ou `{"state":"idle"}`) |
| `cancel` | cria `$VDLU_DIR/cancel` (um `run` em andamento para no próximo ponto seguro) |

Fonte de blobs/manifesto: `source` da config. `<source>` + `/manifest.json`, `/blobs/<sha>`, `/blobs/<sha>.gz`.
`source` começa com `https://` (curl estático buscado, TLS) ou `file://` (staging local).

## 3. manifest.json (produzido pelo PRODUCER, consumido pelo ENGINE)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":5, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = a árvore-alvo COMPLETA. `class`: `live` (webroot/bin/lib/confs/scripts-sob-demanda/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`, `system/**`, `*.rule`).
  Padrão por path, nunca rebaixa `reboot`→`live`.
- `enc`: `gz` (gzip `-9 -n`, determinístico, gunzip do toybox no device) só quando comprime bem E o
  tamanho é significativo, `sha256` é SEMPRE do conteúdo original.
- `sig`: assinatura do manifesto canônico SEM o campo `sig` (§4 do verify).
- **Exclusão da âncora de confiança (no engine, VDLU#2):** o engine DESCARTA do plano qualquer path `files[]`/`delete[]` sob `vdlu/` (seu próprio `update.sh`/`vdlu-verify`/`verify/*`/`keyring/*`/config) - nunca buscado, aplicado ou deletado - mesmo se um feed assinado os carrega. A âncora de confiança on-device muda apenas por um re-flash assinado completo, não pela rede, o `vdlu-pack` também exclui `vdlu/` no lado do producer, então esta é uma segunda guarda, no engine, contra uma chave de assinatura vazada.

## 4. journal.json (o ENGINE escreve, a WEBUI lê - o contrato de progresso)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

Máquina de estados (ordem fixa): `PLANNED→FETCHING→FETCHED→APPLYING→APPLIED_LIVE→(PENDING_REBOOT|DONE)`.
`DONE` só depois de um re-hash de TUDO bater. Um REBOOT-hard encenado ⇒ `PENDING_REBOOT` (não `DONE`). Saídas
da fase `fetch`: `ERROR` (falha dura) ou `DEFERRED` (o net_policy bloqueou o download - benigno/retomável,
não um erro).

## 5. config (key=value, um por linha, editável na WEBUI)

```
auto_on_webui_open=0
auto_on_reboot=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=trusted        # trusted | hardened. CODE DEFAULT (line absent) = hardened (fail-closed, 9a9a824)
net_policy=any         # any (Wi-Fi+mobile) | wifi (Wi-Fi only) | mobile (mobile only) - gates the DOWNLOAD by network type
allow_metered=0        # ⚠️ SUPERSEDED by net_policy (not consumed by the engine)
pubkey_dir=keyring     # relative to $MODULE_DIR/vdlu (keyring of pubkeys for verify)
key_id=                # ALLOWLIST of accepted MODULE-UPDATE signing key id(s), comma-separated (rotation).
                       # UNSET = default-safe: a single-key keyring accepts only that one key; a MULTI-key
                       # keyring (one that also ships a fingerprint-feed key) MUST pin its module key here.
ca_path=               # empty = auto-detect of the Android trust store; set a path to override
ca_cert=               # empty = auto-build a CA bundle from the trust store; set a path to a bundle to override
tools_source=          # empty = derived from source (.../vdlu-tools); feed of the static curl
apply_busy_file=       # OPT-IN: absolute path the host module touches during its own operations (e.g. a
                       # backup). While it EXISTS, APPLY is deferred to the next trigger (blobs already
                       # fetched, no re-download) so an update never swaps module files mid-operation. UNSET = off.
boot_retry_interval=30 # seconds between probes when BOOT finds the device offline (floor 5s)
boot_retry_minutes=0   # ceiling of the PATIENT retry (AWAKE-time) only at boot; 0 = off. Battery-safe (no wakelock,
                       # no held lock, route probe never wakes the radio) -> a generous ceiling is ~free
```

**Boot retry (offline) - PACIENTE, seguro para a bateria:** só no `boot` (nunca no check/auto-open). Se o fetch
do manifesto falhar por REDE (`fetch_offline` classifica pelo exit do fetcher), ele espera e tenta de novo até
sucesso OU até esgotar `boot_retry_minutes` de tempo ACORDADO. Um design que **não retém nada e não drena**:
- **Zero wakelock:** entre tentativas é um `sleep`, que congela em deep-sleep → o device dorme normalmente
  (~zero bateria), o retry pausa e retoma assim que o device já está acordado.
- **Zero lock retido:** `acquire_lock_try`+release ENTRE tentativas (não segura o lock enquanto espera) →
  `run`/check manual nunca bloqueiam, se um run manual encenar um TARGET nesse meio-tempo, o boot adia.
- **Não acorda o rádio à toa:** uma sonda `net_allowed` (via `net_type`/`ip route get`, um lookup de rota de
  kernel que respeita o policy-routing do Android, sem pacote) gateia cada tentativa - só gasta um fetch quando a
  rede tiver aparecido.
- NUNCA repete uma falha determinística (manifesto/sig/downgrade). `--connect-timeout 15` no fetch (não trava
  num captive portal). O `service.sh` o joga para background (o boot nunca trava).
- ⛔ **DURO: ligar `boot_retry_minutes>0` exige o engine PACIENTE** (o que tem
  `net_allowed`+`acquire_lock_try`, canônico `da7115f4`+). O boot-retry ANTERIOR (segura o lock a janela inteira
  + repete curl cego offline) **DRENA a bateria/acorda o rádio** - ligar o retry num engine antigo é um footgun.
  Ao habilitá-lo, vendorize o engine atual.

**`net_policy` (any|wifi|mobile):** gateia o **DOWNLOAD** por tipo de rede. `net_type()` classifica o egress
do `ip route get` (iface celular `rmnet/ccmni/v4-*/clat` = mobile, tudo o mais = wifi, lookup de kernel, sem
pacote). `net_allowed()` compara contra `net_policy` e gateia `do_fetch` (blobs) + a sonda do boot-retry
paciente. O **check do manifesto permanece livre** (minúsculo → a UI reporta uma atualização em qualquer rede);
só o download espera pela rede permitida. Um download numa rede não-permitida = o estado **`DEFERRED`** no
journal (NÃO ERROR, um toast INFO azul suave "aguardando rede X", plan/target persistem, retoma no próximo
check/boot na rede certa). `net_policy` **supera** `allow_metered` (que nunca foi consumido). Engine `97baf887`+
(`file://` nunca é gateado).

## 6. Assinatura (o PRODUCER assina no PC via openssl, o ENGINE verifica no device via ed25519-mini)

- Canonicalização: o manifesto SEM `sig`, chaves ordenadas, JSON compacto (sem espaços supérfluos), UTF-8.
  O que é assinado/verificado = o hex `sha256` dessa forma canônica (dá determinismo cross-tool).
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` → injeta `key_id` + `sig` (base64 da assinatura ed25519 do sha256 canônico) no manifesto, in place.
- `engine/vdlu-verify <manifest.json> <keyring_dir>` → rc 0 se a `sig` bate com a pubkey `<key_id>.pub` no
  keyring (SLIM: pubkey **RAW 32 bytes**). Internamente, sem openssl: `sha256sum`/`base64 -d` do toybox + o
  binário `ed25519-mini` embarcado (CLI `ed25519-mini <pub32> <msg> <sig64>`, rc 0=válido/1=inválido/2=uso).
  rc!=0 = rejeita. **`profile=hardened` ⇒ verify obrigatório, falha = aborta.**
  `profile=trusted` ⇒ verify é best-effort (fonte já confiável via SSH), mas o hash de todo blob é SEMPRE conferido.
- **Allowlist de chave de module-update (fail-closed, antes da seleção da pubkey):** o `key_id` do manifesto precisa ser uma chave MODULE-UPDATE aceita antes de `<key_id>.pub` ser selecionada - o `key_id` da config (§5) é essa allowlist. Um keyring pode TAMBÉM carregar uma chave de menor confiança (ex.: uma chave de fingerprint-feed, automatizada, de outra conta), sem a allowlist, um manifesto assinado por essa chave verificaria e aplicaria uma atualização root flashless completa se vazasse. O `verify_manifest` impõe isso em AMBOS os profiles e passa o conjunto resolvido ao `vdlu-verify` pela env `VDLU_KEYID_ALLOW` (para o verificador standalone concordar). Não-definido é seguro por padrão (keyring de chave única: só aquela chave, keyring multi-chave: rejeitado até `key_id` ser fixado). A raiz de confiança do fingerprint-feed é um caminho SEPARADO, com sua própria chave fixada, e não é afetada.
- `producer/vdlu-keygen <id> <out>` → gera `<id>.pem` (priv) + `<id>.pub` (PEM, para tooling no PC) +
  `<id>.pub.raw` (**RAW 32B** = o `<id>.pub` do keyring enxuto no device). openssl `genpkey -algorithm ed25519`.

## 7. Blob - verificação (ENGINE)

Baixa `<source>/blobs/<sha>` (ou `.gz` se `enc=gz`), escreve `.part`, se `gz` descomprime (`gunzip`),
confere `sha256sum` == o `sha256` do manifesto, bateu → `mv` atômico para `$VDLU_DIR/blobs/<sha>`. 3 falhas no
mesmo blob = aborta a fase (nada aplicado). Um blob já em `$VDLU_DIR/blobs/<sha>` com hash ok = pula o download.

## 8. APPLY por classe (ENGINE)

- `live`/`soft`: backup `rollback/<v>/<path>` → escreve `$MODULE_DIR/<path>.vdlu-tmp` a partir do blob → `chmod mode` →
  `rename` atômico sobre o alvo. Já no hash-alvo = pula. (Na variante Zygisk a escrita vai para o dir montado =
  merge por arquivo, nunca `rm -rf` do dir.)
- `reboot`: materializa em `$VDLU_DIR/staged/<path>.vdlu-new` (NÃO toca no vivo). O swap é no `boot`.
- `delete[]`: backup → remove.

## 9. WEBUI ↔ ENGINE (componente WEBUI)

- Dispara: `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (background).
- Progresso: um poll leve `ksu.exec("cat $VDLU_DIR/journal.json")` a cada ~1s, renderiza `{phase,state,total,done,current,bytes}`.
- Liveness: journal ausente por 8 ticks ⇒ "sem resposta". Journal CONGELADO (mesmos valores) por 20 ticks ⇒ confere `lock.d`: vivo = segue (fetch lento de 1 blob), morto = erro + Resume. Sem isso, um run que morreu no meio do fetch congelaria o toast em "atualizando".
- Cancel: `ksu.exec("touch $VDLU_DIR/cancel")`.
- Config: lê/escreve `$VDLU_DIR/config` (key=value) numa aba "Updates".
- Toast: barra + `phase done/total · current`, ao terminar com `reboot_pending` ⇒ um banner persistente "reiniciar para ativar a .so".
- Auto-open (`auto_on_webui_open=1`): faz um `check()` QUIETO primeiro (sem toast de progresso), só dispara o `run`+toast persistente se `update && fetch>0`. Atualizado/à-frente/nada-novo = um resultado inline no painel, zero toast residual. Não-intrusivo como o botão manual (o toast só aparece quando há um download real). O bootstrap do curl é único.

## 10. Integração no demo (componente INTEGRATION) - SNIPPETS, não edite os arquivos vivos

Produz, em `integration/demo/`, snippets + um `INTEGRATION.md` dizendo onde cada um entra (sem aplicar):
- o hook `auto_on_reboot` em `post-fs-data`/`service.sh` (pré-zygote → `update.sh boot`) e `auto_on_webui_open`.
- os defaults do `config` + o keyring embarcado + a vendorização (`modules/<mod>/vdlu/`).
- a variante PARCIAL (merge no dir montado).

## 11. Toolchain buscada + baseline (SLIM, Abordagem B)

**Layout no módulo (zip):** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`. **SEM** `bin/` (openssl/curl/zstd). O `customize.sh` pode podar
`verify/` até a ABI do device (`vdlu-verify` acha o mini em `<dir>/ed25519-mini` OU `<dir>/verify/<abi>/ed25519-mini`).

**ed25519-mini** (binário embarcado, só-verify): `ed25519-mini <pubkey32> <msg> <sig64>` → rc 0=válido,
1=inválido, 2=uso/IO. msg = os bytes assinados exatos (NÃO re-hasheia). TweetNaCl PD, estático por ABI, PROVENANCE.

**tools-feed** (só perfil public/https): servido em `<tools_source>` (default derivado: troca o último segmento
de `source` por `vdlu-tools`, ex. `https://<user>.github.io/<repo>/vdlu-tools`). Contém:
- `tools-manifest.json` - um manifesto `vdlu-pack` ASSINADO sobre a árvore `<abi>/curl`, fixando o `sha256` de
  cada curl (mesma chave `release-2026`).
- `<abi>/curl` - o curl **estático** CRU (autocontido, ~1MB, curl 8.11.1 + mbedTLS). 🪤 o mbedTLS NÃO
  carrega um bundle de CA: `fetch_url` passa `--capath` (auto-detecção do trust store do Android: `/system/etc/security/cacerts`
  → APEX conscrypt, `ca_path` sobrepõe). Sem capath = erro 60. A integridade é o ed25519, o cert-check é defesa-em-profundidade.

**install-tool** (ENGINE): `update.sh install-tool <abi>` lê `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}`
(a WEBUI o baixa via `fetch()` e o escreve ali), **verifica a assinatura do tools-manifest (ed25519-mini,
OBRIGATÓRIO em qualquer perfil)** + o hash do curl == manifesto, e só então o instala em `$VDLU_DIR/tools/<abi>/curl` (0755).
O curl roda como root → sig+hash antes do exec fecha o RCE. Persiste em Tier-2: nunca re-baixado (exceto no uninstall).

**fetch-bootstrap** (WEBUI, `ensureToolchain()`): roda antes de check/run/resume. `file://` = no-op, curl JÁ
disponível (Tier-2, OU `module/bin/<abi>/curl` de um módulo **auto-embarcado**, OU sistema) = no-op
(o VDLU reaproveita o curl existente), só `https` **sem curl algum** baixa curl + tools-manifest via webview, os escreve
em `.work` (base64 em chunks via `ksu.exec`), chama `install-tool`. Confiança = o check on-device, não o download.

> 🪤 **Slim (fetch-bootstrap) ≠ obrigatório.** Um módulo cujo `bin/` existe para SUAS PRÓPRIAS features (ex. embarca
> restic/rclone/age/tar/curl...) **não** enxuga para ~2MB nem baixa curl - o VDLU adota o engine enxuto
> (gz, mini, baseline, fixes) e **reaproveita** a toolchain embarcada. Só módulos sem toolchain própria
> ganham os ~2MB.

**baseline.json** (fix de from:0): o release copia o `manifest.json` ASSINADO da versão embarcada para
`vdlu/baseline.json`, numa instalação limpa o engine semeia `current.json` a partir dele (`init_paths`, só se ausente) → o
device nasce "atualizado", sem auto-update de si mesmo e sem re-fetch.

<!-- doc-footer -->

---

> _Esta documentação foi gerada com o Claude (Anthropic) e é mantida por VD171. Correções e melhorias são bem-vindas, veja [CONTRIBUTING.md](CONTRIBUTING.md)._
