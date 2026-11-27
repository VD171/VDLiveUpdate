> **Languages:** [English](../ENGINE.md) · [العربية](../ar/ENGINE.md) · [Čeština](../cs/ENGINE.md) · [Deutsch](../de/ENGINE.md) · [Español](../es/ENGINE.md) · [فارسی](../fa/ENGINE.md) · [Français](../fr/ENGINE.md) · [हिन्दी](../hi/ENGINE.md) · [Bahasa Indonesia](../id/ENGINE.md) · [Italiano](../it/ENGINE.md) · [日本語](../ja/ENGINE.md) · [한국어](../ko/ENGINE.md) · [Nederlands](../nl/ENGINE.md) · [Polski](../pl/ENGINE.md) · Português · [Русский](../ru/ENGINE.md) · [Svenska](../sv/ENGINE.md) · [ไทย](../th/ENGINE.md) · [Türkçe](../tr/ENGINE.md) · [Українська](../uk/ENGINE.md) · [Tiếng Việt](../vi/ENGINE.md) · [中文](../zh/ENGINE.md)

---

# Engine VDLU (`update.sh`)

Cliente de atualização flashless e incremental para módulos KSU/Magisk. Implementa o ciclo
`DIFF -> FETCH -> APPLY -> COMMIT` como uma transação retomável. Conforma-se a `INTERFACES.md` (a lei
da convergência).

sh POSIX puro (mksh/busybox/toybox). **SLIM:** depende só de toybox (`sha256sum`/`gzip`/`base64`/`date`) +
o `ed25519-mini` embarcado (verify ed25519, **sem openssl no device**) + um `curl` estático **buscado** na
primeira atualização https (a WebUI faz o `fetch()`, o persiste em Tier-2, e o `install-tool` verifica sua
assinatura+hash ANTES de usar). `file://` não precisa de curl. Zero dependência de `jq`.

## Invocação

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = ok, `rc != 0` = erro (motivo no stderr). `vdlu-verify` é entregue por outro componente
(assinatura em `INTERFACES.md §6`), o engine apenas o chama.

| cmd | faz |
|---|---|
| `check` | DIFF somente-leitura; imprime `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; não muda nada |
| `run` | ciclo LIVE completo + encena REBOOT-hard; honra `cancel`; progresso em `journal.json` |
| `resume` | retoma a transação pendente (`target.json`) a partir da fase atual; idempotente; **não** faz swap da `.so` |
| `boot` | modo pré-zygote: resume **+** faz swap dos `staged/*.vdlu-new` → fecha `PENDING_REBOOT`→`DONE`. Sem transação pendente, roda um ciclo novo e aplica tudo (inclusive a `.so`) num único boot |
| `status` | imprime `journal.json` (ou `{"state":"idle"}`) |
| `cancel` | cria `$VDLU_DIR/cancel`; um `run` em andamento para no próximo ponto seguro |

## Máquina de estados (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE` só depois de um re-hash de TUDO bater. Se qualquer REBOOT-hard foi encenado ⇒ `PENDING_REBOOT` (nunca um
`DONE` falso). `ERROR` em qualquer falha, sem corromper o módulo (os arquivos LIVE aplicados são revertidos
de `rollback/<v>/`, nada "meio-aplicado mentindo sobre isso"). Saída benigna da fase `fetch`: **`DEFERRED`** -
o download foi adiado pelo `net_policy` (rede não permitida), plan/target persistem e retoma no próximo
check/boot (a WebUI mostra um toast info azul "aguardando rede X", não um erro).

## Garantias de rigor

- **FETCH:** gateado pelo `net_policy` (any/wifi/mobile, só http/https, `file://` nunca) - uma rede não permitida ⇒
  `DEFERRED` (retomável), sem gastar dados. Baixa só o que falta para `<sha>.part` (curl com
  `--connect-timeout` + `--speed-time`, nunca trava), descomprime `gz` (toybox `gunzip`), confere `sha256sum` ==
  manifesto, `mv` atômico para `blobs/<sha>`. Um blob em cache+ok é pulado. Pode semear o blob a partir de um arquivo
  local inalterado (dedup/offline). **3 falhas no mesmo blob = a fase aborta sem aplicar nada.** Só
  vira `FETCHED` com TODOS os blobs do plano presentes+verificados. Na configuração da toolchain
  ele loga a confiança TLS resolvida (path da CA + legibilidade, tamanho do bundle e contagem de
  certs) para que um curl `rc 77` em tempo de boot seja autoexplicativo no `boot.log` - ele
  distingue um store vazio de um ilegível (o caso de contexto SELinux no boot).
- **APPLY** (só a partir de `FETCHED`): `live`/`soft` → backup para `rollback/<v>/` → `.vdlu-tmp` → `chmod` → verify →
  `rename` atômico. `reboot` → materializa em `staged/<path>.vdlu-new` (NÃO toca no inode vivo).
  `delete[]` → backup → remove. Idempotente (um arquivo já no hash-alvo é pulado).
- **COMMIT:** re-hash de todo `live`/`soft`, só então escreve `current.json`. Com arquivos encenados ⇒
  `PENDING_REBOOT`. `boot` faz `mv -f staged/....vdlu-new $MODULE_DIR/<path>` (pré-zygote) + re-verifica +
  `DONE`.
- **cancel:** conferido entre arquivos (ponto seguro), remove o `.vdlu-tmp`/`.part` em voo, apaga `cancel`,
  deixa o journal retomável (`cancelled:true`, `error:null`).
- **mkdir-lock `$VDLU_DIR/lock.d`** serializa (flock é inviável no toybox, recuperação de stale por PID). O
  boot-retry PACIENTE não segura o lock enquanto espera (`acquire_lock_try`+release entre tentativas) nem um
  wakelock - seguro para a bateria. Um crash/rede/reboot no meio → `resume`/`boot` continua.
- **profile=hardened** ⇒ `vdlu-verify` obrigatório no manifesto ANTES de usar, falha = aborta, downgrade bloqueado
  (versão monotônica). **trusted** ⇒ verify é best-effort, mas o hash de todo blob é SEMPRE conferido.
- **Allowlist de chave de module-update (ambos os profiles):** o `verify_manifest` rejeita, fail-closed, qualquer manifesto cujo `key_id` não esteja na allowlist `key_id` configurada (ver INTERFACES §5/§6) ANTES de a pubkey ser selecionada, então uma chave de menor confiança que apenas reside no keyring (ex.: uma chave de fingerprint-feed) nunca pode assinar uma atualização root flashless. Seguro por padrão quando não-definido: keyring de chave única = só aquela chave, keyring multi-chave = rejeitado até `key_id` ser fixado.
- **Exclusão da âncora de confiança (VDLU#2):** o engine IGNORA todo path `vdlu/` em um plano buscado (`update.sh`, `vdlu-verify`, `verify/*`, `keyring/*`, config) - nunca buscado, aplicado ou deletado - mesmo se um feed assinado os carrega. Um feed nunca pode trocar o verificador on-device ou a chave de assinatura, a âncora de confiança muda apenas por um re-flash assinado completo, então uma única chave de assinatura vazada não pode persistir root pela rede.
- **Adiamento por ocupado (opt-in `apply_busy_file`):** com `apply_busy_file` definido (um path absoluto que o módulo host toca durante suas próprias operações, ex. um backup em andamento), o APPLY é adiado enquanto esse path existe - uma atualização nunca troca arquivos do módulo no meio de uma operação. Os blobs já estão buscados, então o próximo trigger aplica sem re-download.
- **Tetos de tamanho:** 128 MiB por arquivo (`MAX_FILE_BYTES`) e 2 MiB por manifesto (`MAX_MANIFEST_BYTES`), impostos antes da leitura tanto em `update.sh` quanto em `vdlu-verify` (anti bomba-de-descompressão / anti-OOM).
- Degrada graciosamente: binário faltando / rede caída / disco cheio → um erro claro no stderr + `state:ERROR` no
  journal, sem corromper o módulo.

## Parsing de JSON sem jq

Um flattener estilo gron em `awk` (POSIX puro: `substr`/`index`/`gsub`/`split`/`printf` + locais passados como
parâmetros) tokeniza o manifesto char-a-char e emite uma linha `path<TAB>value` por folha escalar
(`files/0/sha256<TAB>ab..`, `version<TAB>6`, `delete/0<TAB>etc/x`). Robusto contra JSON compacto OU
pretty-printed. O `sh` o consome com `grep`/`cut`, o plano por arquivo é remontado num 2º `awk` em TSV
(`class st mode enc sha size path`), que vira `$VDLU_DIR/plan.tsv`.

## Arquivos de estado (em `$VDLU_DIR`, Tier-2)

| arquivo | papel |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`key_id`/`apply_busy_file`/`boot_retry_*`/…; ver INTERFACES §5) |
| `current.json` | manifesto da versão ATIVA (base do diff); ausente = nunca atualizado |
| `target.json` | manifesto fixado da transação em voo (presença = transação ativa); vira `current.json` no `DONE` |
| `plan.tsv` / `plan.del` | plano + progresso por arquivo (st) / paths a deletar |
| `journal.json` | progresso para a WebUI (regenerado a cada transição) |
| `blobs/<sha256>` | cache de conteúdo original verificado |
| `rollback/<version>/<path>` | backup de arquivos sobrescritos (undo; mantém os últimos 3) |
| `staged/<path>.vdlu-new` | REBOOT-hard aguardando swap no boot |
| `lock.d/` | mkdir-lock (flock inviável no toybox; recuperação de stale por PID) |
| `tools/<abi>/curl` | curl estático buscado (bootstrap enxuto); persiste entre atualizações |
| `cancel` | pedido de cancelamento |

<!-- doc-footer -->

---

> _Esta documentação foi gerada com o Claude (Anthropic) e é mantida por VD171. Correções e melhorias são bem-vindas, veja [CONTRIBUTING.md](CONTRIBUTING.md)._
