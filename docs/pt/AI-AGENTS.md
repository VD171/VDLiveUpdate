> **Languages:** [English](../AI-AGENTS.md) · [العربية](../ar/AI-AGENTS.md) · [Čeština](../cs/AI-AGENTS.md) · [Deutsch](../de/AI-AGENTS.md) · [Español](../es/AI-AGENTS.md) · [فارسی](../fa/AI-AGENTS.md) · [Français](../fr/AI-AGENTS.md) · [हिन्दी](../hi/AI-AGENTS.md) · [Bahasa Indonesia](../id/AI-AGENTS.md) · [Italiano](../it/AI-AGENTS.md) · [日本語](../ja/AI-AGENTS.md) · [한국어](../ko/AI-AGENTS.md) · [Nederlands](../nl/AI-AGENTS.md) · [Polski](../pl/AI-AGENTS.md) · Português · [Русский](../ru/AI-AGENTS.md) · [Svenska](../sv/AI-AGENTS.md) · [ไทย](../th/AI-AGENTS.md) · [Türkçe](../tr/AI-AGENTS.md) · [Українська](../uk/AI-AGENTS.md) · [Tiếng Việt](../vi/AI-AGENTS.md) · [中文](../zh/AI-AGENTS.md)

---

# Operar o VDLU a partir de um agente de IA

O VDLiveUpdate (VDLU) é o atualizador incremental e flashless que os módulos KSU/Magisk vendorizam em `vdlu/`. O motor inteiro é operado pelo shell, então um assistente ou agente de IA pode verificar, aplicar, retomar e concluir uma atualização de forma headless, o mesmo ciclo que a WebUI roda, sem UI e sem humano no circuito. Interprete o JSON que ele imprime, nunca raspe texto.

## O contrato

Um único ponto de entrada, executado como root no aparelho, com as três variáveis de ambiente do motor definidas:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <verb>
```

- `VDLU_DIR` é o diretório de estado Tier-2 (fora do módulo, sobrevive a um reflash), `MODULE_DIR` é a árvore viva do módulo, `MODID` é o id do módulo.
- `rc 0` = ok, `rc != 0` = erro, com o motivo no stderr.
- Os verbos de leitura (`check`, `status`) imprimem **um objeto JSON** no stdout. Interprete isso, nunca raspe texto.
- O motor depende apenas do toybox (`sha256sum`/`gzip`/`base64`) mais um `ed25519-mini` embarcado mais um `curl` estático baixado na primeira atualização https, zero `jq`.

Durante o desenvolvimento o mesmo script fica em `engine/update.sh` neste repositório, então `sh engine/update.sh <verb>` com as três variáveis definidas opera uma cópia de testes do mesmo jeito.

## Verbos

| Verbo | Faz | Imprime |
|------|------|--------|
| `check` | DIFF somente leitura contra o feed, não muda nada | `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`, ou `{"update":false,"ahead":true,"from":N,"to":M}` quando o aparelho está à frente do feed (downgrade bloqueado, benigno, rc 0) |
| `run` | ciclo LIVE completo DIFF -> FETCH -> APPLY -> COMMIT, aplica os arquivos LIVE e encena os REBOOT-hard, honra o `cancel` | progresso em `journal.json` |
| `resume` | retoma a transação pendente a partir da fase atual, idempotente, nunca troca o `.so` | `journal.json` atualizado |
| `boot` | modo pre-zygote, `resume` mais a troca do `.so` encenado, fecha `PENDING_REBOOT` em `DONE` | `journal.json` atualizado |
| `status` | snapshot somente leitura, não muda nada | `journal.json`, ou `{"state":"idle"}` quando nenhuma transação está ativa |
| `cancel` | pede uma parada, um `run` em andamento para no próximo ponto seguro | cria `$VDLU_DIR/cancel` |

Uma atualização headless é `check` para ver se há algo pendente, `run` para aplicar tudo que pode ir ao vivo, e então `boot` no próximo boot para trocar qualquer `.so` encenado (ou `resume` para repetir um fetch adiado). Todo verbo é seguro de chamar de novo, uma falha ou uma queda de rede no meio do ciclo deixa um journal retomável, nunca um módulo meio aplicado.

## JSON de status

O `status` (e o arquivo vivo em `$VDLU_DIR/journal.json`) é o contrato de progresso que a WebUI e um agente leem:

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit",
  "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>,
  "reboot_pending":bool, "cancelled":bool, "error":"<str|null>",
  "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

- `state` avança em ordem fixa: `PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)`.
- `DONE` só é alcançado depois que um re-hash de tudo bate. Um arquivo REBOOT-hard encenado resulta em `PENDING_REBOOT`, nunca um `DONE` falso, rode `boot` para concluí-lo.
- `DEFERRED` significa que o `net_policy` bloqueou o download, um estado benigno e retomável e não um erro, o plano persiste e o próximo `check`/`boot` continua.
- `ERROR` carrega o motivo em `error`, os arquivos LIVE aplicados são revertidos de `rollback/`, o módulo nunca fica meio aplicado.
- `cancelled:true` com `error:null` é uma parada limpa, o journal permanece retomável.

## O contrato de costura

Todo componente (motor, produtor, WebUI) se conforma a [`INTERFACES.md`](INTERFACES.md), a lei de convergência. Os verbos da CLI, o schema do `manifest.json`, as chaves do `journal.json` e as chaves de config definidas ali são **imutáveis**, trate esse arquivo como a única fonte da verdade e alinhe-se a ele antes de mudar qualquer um deles. Para os internos do motor (a transação retomável, as garantias de rigor, a exclusão do trust-anchor) veja [`ENGINE.md`](ENGINE.md), para o lado do feed (construir e assinar o feed endereçado por conteúdo) veja [`PRODUCER.md`](PRODUCER.md).

## Regras para um agente

- Use os verbos e o JSON, nunca raspe a WebUI e nunca edite os arquivos de estado à mão.
- Trate `INTERFACES.md` como imutável, uma mudança significa alinhar o contrato primeiro.
- Um patch de um agente de IA passa pela mesma barra de revisão que qualquer outro, build sempre release, não afrouxe nada, não perca nada.

<!-- doc-footer -->

---

> _Esta documentação foi gerada com o Claude (Anthropic) e é mantida por VD171. Correções e melhorias são bem-vindas, veja [CONTRIBUTING.md](CONTRIBUTING.md)._
