# VDLiveUpdate (VDLU)

**O VDLU é um motor de autoatualização flashless e incremental para módulos KernelSU / APatch / Magisk: um módulo instalado atualiza seus próprios arquivos por um feed assinado, buscando apenas o que mudou e aplicando a maior parte sem reiniciar.**

Uma atualização normal de módulo reenvia o `.zip` inteiro, então algumas linhas alteradas custam um re-download completo, e um manifesto de atualização estático só pode apontar para um único `zipUrl` (um único flavor para todo dispositivo). O VDLU segue um caminho diferente: ele faz o diff da árvore que está realmente instalada contra um feed assinado e endereçado por conteúdo, baixa apenas os deltas e os grava no lugar. Uma instalação full arm64 continua full arm64, uma instalação lite continua lite, e o módulo nunca é reflashado.

O VDLU foi pensado para ser **vendorizado** dentro de um módulo, colocado em `<module>/vdlu/`. Ele não é um módulo próprio.

## Objetivos

- **Autoatualização flashless.** Atualizar um módulo instalado no lugar, pela rede, sem root manager, sem reflash do `.zip` e sem perder o flavor instalado.
- **Incremental por conteúdo.** Transferir apenas os blobs cujo conteúdo mudou. Um feed endereçado por conteúdo (`manifest.json` + `blobs/<sha256>`) significa que arquivos inalterados ou revertidos nunca são buscados de novo.
- **Sem reinício quando é seguro.** Aplicar arquivos comuns ao vivo, imediatamente. Reservar um reinício em estágio apenas para os poucos arquivos que realmente precisam dele (um `.so`, um overlay de `/system`, um `sepolicy.rule`).
- **Enxuto no dispositivo.** `sh` POSIX puro, sem `jq`, sem `bash`, sem `openssl` no dispositivo. A verificação se apoia em um `ed25519-mini` embarcado; o único binário buscado é um `curl` estático, usado apenas para feeds `https`.
- **Fail-closed e honesto.** Todo campo do manifesto é tratado como entrada hostil e validado antes de qualquer download. Nada é reportado como "concluído" a menos que um re-hash prove isso, e nada é sobrescrito sem um backup antes.

## Peculiaridades

O que torna o VDLU diferente de um cliente OTA típico:

- **Flashless e incremental.** Diff / fetch / apply endereçado por conteúdo com dedup: o dispositivo computa o delta contra o feed assinado e puxa apenas os blobs faltantes.
- **Sem reinício quando possível.** Arquivos comuns aplicam ao vivo; apenas arquivos `.so`, overlays de `/system` e `sepolicy.rule` são estagiados e trocados em um único reinício. Veja [[Reboot Handling]].
- **`sh` POSIX no dispositivo.** Roda sob toybox / busybox / mksh. Sem `jq` (um flattener `awk` estilo `gron` parseia o JSON), sem `bash`ismos, sem runtime pesado.
- **Verificação enxuta.** Um `ed25519-mini` embarcado verifica assinaturas. **Não há `openssl` no dispositivo**; a chave privada nunca toca um dispositivo ou CI.
- **Segurança fail-closed.** O `validate_plan()` rejeita o manifesto **inteiro** em qualquer campo inválido (caminho absoluto ou `..`, um `sha256` que não tem 64 caracteres hex, um mode / class / encoding inválido). Dois perfis, `trusted` e `hardened`, com o `hardened` fail-closed por inversão. Veja [[Security and Trust Model]].
- **Resumível e atômico.** Um journal torna toda transação à prova de crash; gravações usam `rename` / `mv`; um backup é feito antes de qualquer sobrescrita, de modo que um apply que falha reverte em vez de corromper o módulo.

## Comece por aqui

| Se você quer... | Vá para |
|---|---|
| Adotar o VDLU no seu módulo, passo a passo | [[Quick Start]] |
| Entender todo o sistema de relance | [[Architecture]] |
| Aprender o motor do lado do dispositivo (`update.sh`) | [[Engine]] |
| Construir e assinar um feed no seu PC | [[Producer]] |
| Encaixar o painel de Updates | [[WebUI]] |
| Ler o modelo de confiança e a postura de ameaça | [[Security and Trust Model]] |
| Ver o layout do manifesto e dos blobs | [[Feed Format]] |
| Saber o que reinicia e por que | [[Reboot Handling]] |
| Fazer uma pergunta comum | [[FAQ]] |
| Contribuir | [[Contributing]] |

## Links do projeto

- **Código-fonte:** https://github.com/VD171/VDLiveUpdate
- **Canal (atualizações):** @Priv8_VD https://t.me/Priv8_VD

O VDLiveUpdate é um projeto independente e não oficial. "Android" é uma marca da Google LLC; "KernelSU", "Magisk" e "APatch" são marcas de seus respectivos autores. O VDLU roda inteiramente no seu dispositivo e no seu próprio host de release.
