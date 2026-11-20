# Architecture

O VDLU tem dois lados unidos por uma única coisa no meio. No PC, o [[Producer]] transforma uma árvore de módulo em um feed assinado e endereçado por conteúdo. No dispositivo, o [[Engine]] lê esse feed, descobre o que mudou e aplica. A junção entre eles é o **manifesto assinado mais o armazenamento de blobs** (o [[Feed Format]]). Nada mais cruza a fronteira.

```
        PC / release host                                device
  +--------------------------+                 +---------------------------+
  |  Producer                |                 |  Engine  (update.sh)      |
  |  vdlu-pack  -> manifest  |    signed       |  POSIX sh, no jq          |
  |  vdlu-sign  -> sig       |    feed         |  DIFF FETCH APPLY COMMIT  |
  |  vdlu-gc    -> prune     | =============>  |  journal + rollback       |
  +--------------------------+   manifest.json |  ed25519-mini verify      |
                                 blobs/<sha>   +-------------+-------------+
                                                             |
                                                       +-----v------+
                                                       |  WebUI     |
                                                       |  Updates   |
                                                       |  panel     |
                                                       +------------+
```

Os dois lados nunca compartilham um runtime. O Producer usa `python3` e `openssl`; o Engine é `sh` POSIX puro com toybox e um `ed25519-mini` embarcado. Eles concordam apenas porque ambos derivam os **mesmos bytes canônicos** de um manifesto (veja [[Security and Trust Model]]). A WebUI é um painel fino em vanilla-JS que dirige o motor pela ponte do root manager e lê seu journal de progresso; ela não contém nenhuma lógica de atualização própria. Veja [[WebUI]].

## Os dois lados

| Lado | Roda em | Construído a partir de | Função |
|---|---|---|---|
| [[Producer]] | PC / CI | `python3` + `sh` + `openssl` | Percorre a árvore do módulo gerando `manifest.json` + `blobs/`, assina, poda órfãos |
| [[Engine]] | dispositivo | `sh` POSIX + toybox + `ed25519-mini` | Faz o diff da árvore instalada contra o feed, busca deltas, aplica, confirma |
| [[WebUI]] | dispositivo (webview) | vanilla JS/CSS | Dispara atualizações, mostra progresso, edita config, mostra o banner de reinício |

## O pipeline de atualização

Toda atualização é uma transação, executada em ordem fixa:

```
  DIFF  ------>  FETCH  ------>  APPLY  ------>  COMMIT
  read feed      download        write live     re-hash all,
  + validate     only missing    files now,      promote target
  + plan         blobs, verify   stage reboot     -> current,
  (no changes)   each sha256     ones             DONE or
                                                  PENDING_REBOOT
```

- **DIFF** (`update.sh check` é esta fase, somente leitura). O motor baixa apenas o manifesto, roda `validate_plan()` sobre cada campo **antes** de tocar em qualquer coisa, depois compara o feed contra `current.json` para montar um plano por arquivo. Não altera nada no disco. Um dispositivo adiante do feed é um resultado benigno de "ahead", não um erro.
- **FETCH.** Baixa apenas os blobs que faltam no plano, para `<sha>.part`, descomprime `gz`, confere `sha256sum` contra o manifesto e `mv` atomicamente cada blob verificado para o cache. Um blob já em cache (ou semeado a partir de um arquivo local inalterado) é pulado, então uma reversão ou um arquivo compartilhado não custa nada. Três falhas em um blob abortam a fase sem aplicar nada. Um download bloqueado pela política de rede sai como `DEFERRED` (resumível), não um erro.
- **APPLY.** Arquivos comuns (`live` / `soft`) são gravados agora: backup para `rollback/<v>/`, grava um `.vdlu-tmp`, `chmod`, verifica e então faz `rename` atômico sobre o alvo. Arquivos de classe reboot são materializados em `staged/<path>.vdlu-new` e o inode ao vivo fica intocado. Uma entrada de `delete[]` é primeiro salva em backup, depois removida. Cada passo é idempotente: um arquivo já no hash alvo é pulado.
- **COMMIT.** Re-hasha todo arquivo ao vivo; apenas se tudo bater o motor promove `target.json` a `current.json`. Se algo foi estagiado, a transação termina em `PENDING_REBOOT`; caso contrário, `DONE`.

## Manifesto e blobs endereçados por conteúdo

O feed é endereçado por conteúdo: o manifesto lista a árvore alvo **completa**, cada arquivo carregado por seu `sha256`, e o armazenamento de blobs guarda uma cópia de cada conteúdo distinto sob `blobs/<sha256>` (ou `blobs/<sha256>.gz`).

- **Dedup.** Conteúdo idêntico em qualquer lugar da árvore, ou entre releases, é um único blob. A publicação é incremental: um blob cujo `sha256` já existe no host nunca é reenviado, e o dispositivo nunca busca de novo conteúdo que já possui.
- **sha256 é do original.** O hash sempre nomeia o conteúdo descomprimido; `enc` (`raw` ou `gz`) apenas registra como aquele blob em particular acaba sendo armazenado. O dispositivo descomprime `gz` com o `gunzip` do toybox, então nenhum compressor extra é embarcado.
- **Estável por flavor.** Como o dispositivo faz o diff contra o que está realmente instalado, o feed pode carregar uma família inteira de módulos; cada instalação puxa apenas os blobs que completam seu próprio flavor.

O layout campo a campo completo está em [[Feed Format]].

## O journal resumível

Toda transação é à prova de crash porque seu progresso vive em um journal (`journal.json`), e o alvo fixado da transação em curso vive em `target.json`. A máquina de estados roda em ordem fixa:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> ( PENDING_REBOOT | DONE )
                                                               \-> ERROR / DEFERRED
```

| Estado | Significado |
|---|---|
| `PLANNED` | Plano montado, nada buscado ainda |
| `FETCHING` / `FETCHED` | Baixando blobs / todos os blobs presentes e verificados |
| `APPLYING` / `APPLIED_LIVE` | Gravando arquivos / todos os arquivos ao vivo gravados |
| `PENDING_REBOOT` | Um arquivo de classe reboot está estagiado, aguardando a troca no boot |
| `DONE` | Re-hash de tudo bateu; `current.json` promovido |
| `ERROR` | Falha grave; módulo deixado sem corrupção, arquivos ao vivo revertidos de `rollback/` |
| `DEFERRED` | Download retido pela política de rede; o plano persiste, resume depois |

`DONE` só é alcançado **após** um re-hash de tudo bater, então o journal nunca afirma que uma atualização meio aplicada está completa. Um crash, uma rede caída ou um reinício no meio deixam um journal resumível; `update.sh resume` (ou `boot`) retoma a partir da fase atual. Veja [[Engine]] para o conjunto de comandos e os arquivos de estado no dispositivo.

## Atomicidade e rollback

Nada é sobrescrito no lugar e nada é perdido:

- **Gravações atômicas.** Cada arquivo aterrissa via um temp (`.vdlu-tmp`) e um `rename` / `mv` atômico, então um leitor nunca vê um arquivo gravado pela metade.
- **Backup antes de sobrescrever.** O conteúdo anterior vai para `rollback/<version>/<path>` antes de o novo arquivo ser renomeado sobre ele (as últimas versões são mantidas). Se um apply falha, os arquivos ao vivo são revertidos da cópia de rollback em vez de ficarem corrompidos. Um backup que falha **aborta** o apply em vez de sobrescrever sem rede de segurança.
- **Serializado.** Um lock baseado em `mkdir` (`lock.d/`, já que `flock` é inviável no toybox, com recuperação de lock obsoleto por PID) serializa execuções concorrentes.

## O princípio sem reinício

A maioria dos arquivos pode ser trocada enquanto o módulo está ao vivo, então o VDLU os aplica imediatamente. Apenas três classes precisam de um reinício, porque um processo ao vivo já as mapeou: um `.so` (carregado pelo Zygisk), um overlay de `/system` e um `sepolicy.rule`. Essas são **estagiadas, nunca gravadas sobre um inode ao vivo**, e trocadas em um único passo pré-zygote no próximo boot. A taxonomia completa e o fluxo de boot estão em [[Reboot Handling]].

## A postura de confiança fail-closed

O feed é a única coisa que cruza do PC para o dispositivo, então o motor trata cada byte dele como hostil. O `validate_plan()` roda na fase DIFF, antes de qualquer download, e rejeita o manifesto inteiro em qualquer campo malformado. A verificação de assinatura usa um `ed25519-mini` embarcado (sem `openssl` no dispositivo), a chave privada nunca toca um dispositivo ou CI, e o perfil `hardened` é fail-closed por inversão, de modo que um valor de perfil corrompido nunca pode aceitar silenciosamente um feed não assinado. O modelo completo, os dois perfis e as ameaças que cada um responde estão em [[Security and Trust Model]].
