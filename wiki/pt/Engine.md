# Engine

O motor é o lado do dispositivo do VDLU: a parte que roda no telefone, decide o que mudou, baixa isso e aplica. É um único script shell POSIX, `engine/update.sh`, mais um checador de assinatura minúsculo, `engine/vdlu-verify`. Ambos são vendorizados no módulo host em `<module>/vdlu/` e executados pelo root.

Todo o motor é construído em torno de uma ideia: uma atualização é uma **transação resumível**. Se o telefone é reiniciado, morto ou perde a rede no meio do caminho, a próxima execução retoma exatamente de onde parou, e o módulo nunca é deixado meio aplicado fingindo estar pronto.

Se você quer a visão geral primeiro, veja [[Architecture]]. Para como as atualizações evitam um reinício sempre que podem, veja [[Reboot Handling]].

## Escrito para o dispositivo, não para o seu laptop

`update.sh` é `sh` POSIX puro. Roda sob mksh, busybox ou toybox, sem recursos exclusivos do bash, e passa no `sh -n`. Isso importa porque o ambiente em um dispositivo Android rooteado é pequeno e estrito.

Em particular, não há `jq`. O VDLU parseia `manifest.json` com um pequeno flattener estilo gron escrito em `awk`: ele percorre o JSON um caractere por vez e emite uma linha `path<TAB>value` por folha (por exemplo `files/0/sha256<TAB>ab..` ou `version<TAB>6`). O shell então lê essas linhas com `grep` e `cut`. Isso funciona tanto em JSON compacto quanto pretty-printed, e nunca invoca uma ferramenta JSON que não está lá.

O motor depende apenas do que o toybox já traz (`sha256sum`, `gzip`/`gunzip`, `base64`, `date`), do verificador `ed25519-mini` embarcado e, para feeds `https://`, de um pequeno `curl` estático que é buscado e verificado uma única vez. Um feed `file://` não precisa de `curl` nenhum.

## Os seis comandos

Você invoca o motor com os caminhos do módulo no ambiente e um comando:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <cmd>
```

O código de saída `0` significa sucesso; qualquer outro código significa um erro, com a razão impressa no stderr.

| Comando | O que faz |
|---|---|
| `check` | Diff somente leitura. Baixa o manifesto, compara com o que está instalado e imprime um resumo JSON de uma linha: `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`. Não altera nada no disco. Se o dispositivo for mais novo que o feed (um downgrade bloqueado) reporta `{"update":false,"ahead":true,...}` com saída `0`, não um erro. |
| `run` | O ciclo ao vivo completo: DIFF, FETCH, APPLY, COMMIT. Aplica todo arquivo ao vivo imediatamente e estagia os poucos arquivos de classe reboot. Respeita `cancel`. Grava o progresso em `journal.json`. |
| `resume` | Continua uma transação que foi interrompida, partindo de qualquer fase em que ela estava. Idempotente. Ele **não** troca um `.so` estagiado (isso é reservado para `boot`). |
| `boot` | O caminho pré-zygote. Faz um `resume` e então troca quaisquer arquivos `*.vdlu-new` estagiados para o lugar, fechando `PENDING_REBOOT` para `DONE`. Se não há transação pendente, roda um ciclo novo e aplica tudo, incluindo o `.so`, naquele único boot. |
| `status` | Imprime `journal.json`, ou `{"state":"idle"}` quando não há nada em andamento. |
| `cancel` | Cria um marcador `cancel`. Um `run` em progresso para de forma limpa no próximo ponto seguro. |

O comando `check` é deliberadamente barato, para que a UI possa lhe dizer que uma atualização existe em qualquer rede. O download de fato é controlado separadamente (veja a fase de fetch abaixo).

## A transação, passo a passo

Todo `run` percorre uma máquina de estados fixa, registrada em `journal.json` para que a WebUI (e você) possa acompanhar:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

**DIFF.** O motor busca `manifest.json`, valida cada campo (veja abaixo e [[Security and Trust Model]]) e faz o diff da árvore alvo assinada contra `current.json`, o manifesto da versão já instalada. O resultado é um plano por arquivo gravado em `plan.tsv`: uma linha por arquivo, carregando sua classe, hash alvo, mode e estado de progresso. Arquivos já no hash alvo são marcados para pular.

**FETCH.** Para cada arquivo ainda necessário, o motor baixa seu blob endereçado por conteúdo de `<source>/blobs/<sha>` (ou `<sha>.gz` quando comprimido), em um arquivo `.part`. Se o blob for gzipado ele é descomprimido, depois seu SHA-256 é conferido contra o manifesto. Apenas em uma correspondência ele é `mv`-ado atomicamente para `blobs/<sha>`. Um blob já em cache com hash correto é pulado inteiramente, e um arquivo local inalterado pode semear o cache sem nenhum download. Três falhas no mesmo blob abortam a fase sem nada aplicado. A fase alcança `FETCHED` apenas após todo blob do plano estar presente e verificado. Para o [[Feed Format]] de onde esses blobs vêm, veja aquela página.

O fetch é controlado pela política de rede: um feed pode ser restrito a apenas Wi-Fi, apenas mobile ou qualquer rede. Quando a rede atual não é permitida, o fetch não falha; ele entra no estado benigno `DEFERRED`, mantém o plano e o alvo fixados, e resume no próximo check ou boot assim que a rede certa aparecer. Nenhum dado é gasto no meio-tempo.

**APPLY.** Só entra a partir de `FETCHED`. Para cada arquivo o motor age por classe:

- arquivos `live` e `soft`: faz backup do arquivo atual para `rollback/<version>/<path>`, grava o novo conteúdo em um irmão `.vdlu-tmp`, dá `chmod`, verifica seu hash e então faz `rename` atômico sobre o alvo. Um arquivo já no hash alvo é pulado.
- arquivos `reboot` (um `.so`, um overlay de `/system`, um `sepolicy.rule`): materializa em `staged/<path>.vdlu-new`. O inode ao vivo nunca é tocado aqui. Veja [[Reboot Handling]].
- deleções: backup, depois remove. Deleções só são aplicadas no fim de tudo, em um `DONE` limpo, nunca enquanto um reinício ainda está pendente.

**COMMIT.** O motor re-hasha todo arquivo live e soft que tocou. Apenas quando todos eles batem ele grava `current.json`, tornando a nova versão a base do diff. Se algum arquivo de classe reboot foi estagiado, o estado vira `PENDING_REBOOT` em vez de `DONE`; a troca e a re-verificação final acontecem depois sob o comando `boot`.

## A prova de falhas por construção

As garantias que tornam isso seguro para rodar sem supervisão:

- **Nada é marcado como `DONE` sem um re-hash correspondente.** `DONE` só é alcançado depois que todo arquivo aplicado foi relido e seu SHA-256 comparado ao manifesto. Um arquivo de reboot estagiado força `PENDING_REBOOT`, nunca um `DONE` falso.
- **Nada é perdido.** Todo arquivo é salvo em backup para `rollback/<version>/` antes de ser sobrescrito, e as últimas três versões são mantidas. Se um apply falha, os arquivos ao vivo são revertidos do backup; o módulo nunca é deixado meio aplicado mentindo sobre isso. `apply_live` aborta de imediato se o passo de backup falha, em vez de sobrescrever sem volta.
- **Tudo é atômico.** O novo conteúdo aterrissa via `rename`/`mv` sobre o alvo, de modo que um leitor sempre vê ou o arquivo antigo ou o novo, nunca uma gravação truncada.
- **Resumível após um crash ou kill.** Um crash, uma rede perdida ou um reinício no meio deixam um journal válido; `resume` (ou `boot`) continua da fase registrada. O design assume que será interrompido.
- **Degrada de forma limpa.** Um binário faltando, uma rede caída ou um disco cheio produzem um erro claro no stderr e `state:ERROR` no journal, sem corromper o módulo.

## O lock

Apenas uma transação pode tocar o estado por vez. `flock` não é confiável no toybox, então o VDLU serializa com um lock de diretório: `mkdir "$VDLU_DIR/lock.d"` tem sucesso para exatamente um chamador e falha para o resto, o que é atômico em qualquer sistema de arquivos são. Um lock obsoleto deixado por um processo morto é recuperado conferindo o PID registrado.

A retentativa paciente no boot (usada quando o dispositivo está offline no boot) **não** segura esse lock enquanto espera. Ele adquire e libera entre tentativas, de modo que um `run` manual nunca é bloqueado por um boot que está esperando a rede, e nunca segura um wakelock. Seguro para a bateria por design. Mais sobre isso em [[Reboot Handling]].

## Verificação de assinatura: `vdlu-verify`

`vdlu-verify` é o checador de assinatura no dispositivo, mantido deliberadamente enxuto:

```
vdlu-verify <manifest.json> <keyring_dir>
```

Saída `0` significa que a assinatura do manifesto é válida contra a chave pública do keyring cujo id corresponde ao `key_id` do manifesto; qualquer outro código é uma rejeição.

O que o torna enxuto é que ele usa **nenhum `openssl` no dispositivo**. Ele lê a chave pública do keyring como um arquivo de **32 bytes brutos**, canonicaliza o manifesto (o texto do manifesto com o campo `sig` removido), faz o hash dele com o `sha256sum` do toybox, decodifica a assinatura em base64 e entrega a chave bruta, a mensagem e a assinatura de 64 bytes ao binário `ed25519-mini` embarcado. O checador também recusa qualquer coisa malformada antes mesmo de verificar: um `key_id` ou `sig` faltando ou vazio, um `key_id` contendo separadores de caminho, uma chave pública que não tem exatamente 32 bytes, ou uma assinatura que não tem exatamente 64 bytes.

A canonicalização é byte a byte idêntica à do assinador do producer, o que é o que faz uma assinatura verificar entre ferramentas. A chave privada correspondente nunca toca um dispositivo ou CI; apenas a chave pública bruta é embarcada. A história completa de confiança, os dois perfis e por que o `hardened` é fail-closed por inversão estão em [[Security and Trust Model]].

O motor chama `vdlu-verify` durante a fase de diff. Sob o perfil `hardened` uma verificação que falha aborta toda a atualização; sob `trusted` a verificação é best-effort, mas o hash de todo blob ainda é sempre conferido, então conteúdo corrompido é pego independentemente do perfil.

## Estado em disco

Todo o estado do motor vive em `$VDLU_DIR` (fora do diretório do módulo), de modo que a própria árvore do módulo só contém arquivos finalizados:

| Caminho | Papel |
|---|---|
| `config` | configurações key=value (source, profile, channel, política de rede, retentativa de boot) |
| `current.json` | manifesto da versão ativa; esta é a base do diff. Ausente significa nunca atualizado |
| `target.json` | o manifesto fixado da transação em curso. Sua presença marca uma transação ativa; ele vira `current.json` no `DONE` |
| `plan.tsv` / `plan.del` | o plano por arquivo e o progresso, e a lista de caminhos a deletar |
| `journal.json` | progresso para a WebUI, reescrito a cada mudança de estado |
| `blobs/<sha256>` | cache de conteúdo original verificado e descomprimido |
| `rollback/<version>/<path>` | backups de arquivos sobrescritos; as últimas três versões são mantidas |
| `staged/<path>.vdlu-new` | um arquivo de classe reboot aguardando a troca no boot |
| `lock.d/` | o lock de mkdir |
| `tools/<abi>/curl` | o curl estático buscado e verificado; persiste entre atualizações |
| `cancel` | um pedido de cancelamento |

## Veja também

- [[Reboot Handling]]: como o sistema de classes mantém a maioria das atualizações sem reinício, e como um `.so` estagiado é trocado pré-zygote.
- [[Security and Trust Model]]: os dois perfis, a validação fail-closed e a cadeia ed25519 de chave bruta.
- [[Feed Format]]: o manifesto e os blobs endereçados por conteúdo que o motor consome.
- [[Architecture]]: como o motor, o producer e a WebUI se encaixam.
