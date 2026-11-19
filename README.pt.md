<!--
  ======================================================================
   VDLiveUpdate (VDLU)  ::  flashless, incremental module updates
   A self-update engine for KernelSU/APatch/Magisk modules: fetch only the
   files that changed, apply the live ones with no reboot, verified by ed25519.

   Copyright (C) 2026  VD171
   SPDX-License-Identifier: Apache-2.0

   Licensed under the Apache License, Version 2.0; you may obtain a copy at
   http://www.apache.org/licenses/LICENSE-2.0

   Site           : https://vd171.ru
   Site           : https://vd.priv8.ru
   Source         : https://github.com/VD171/VDLiveUpdate
   GitHub         : @VD171 https://github.com/VD171
   XDA-Developers : @VD171 https://xdaforums.com/m/vd171.4699873/
   Telegram       : @VD_Priv8 https://t.me/VD_Priv8
   Channel        : @Priv8_VD https://t.me/Priv8_VD
   Discord        : @VD.Priv8 https://discord.com/users/1296831918989639721
   E-mail         : vd.priv8@pm.me
  ======================================================================
-->

# VDLiveUpdate

> **Languages:** [English](README.md) · [العربية](README.ar.md) · [Čeština](README.cs.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [فارسی](README.fa.md) · [Français](README.fr.md) · [हिन्दी](README.hi.md) · [Bahasa Indonesia](README.id.md) · [Italiano](README.it.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Svenska](README.sv.md) · [ไทย](README.th.md) · [Türkçe](README.tr.md) · [Українська](README.uk.md) · [Tiếng Việt](README.vi.md) · [中文](README.zh.md)

O **VDLU** é um motor de autoatualização incremental e sem flash para módulos **KernelSU / APatch / Magisk**. Um módulo instalado se atualiza sozinho baixando **apenas os arquivos que mudaram** (blobs endereçados por conteúdo + um manifesto assinado), aplica os que são aplicáveis ao vivo **sem reboot** e encena e sinaliza os poucos que realmente precisam de um (um `.so`, um overlay de `/system`, uma `sepolicy.rule`). Sem gerenciador de root, sem rebaixar o `.zip` inteiro, sem reboot a não ser pelos arquivos encenados.

Ele foi feito para ser **vendorizado** dentro de um módulo (copiado para `<module>/vdlu/`), e não para rodar como um módulo em si.

## Por quê

Uma atualização normal de módulo entrega o `.zip` inteiro de novo. Para um módulo grande, isso significa um rebaixamento enorme por causa de poucas linhas alteradas, e um manifesto de atualização estático só consegue apontar para um `zipUrl`, então não consegue servir o flavor (ABI, full vs lite) que o aparelho realmente tem. O VDLU compara a árvore **instalada** com um feed assinado e baixa apenas os deltas, então um install arm64-full continua arm64-full, um install lite continua lite, e a maioria das atualizações se aplica ao vivo.

## Como funciona

- **Produtor (PC / release):** o `vdlu-pack` transforma a árvore de um módulo em um feed endereçado por conteúdo (`manifest.json` + `blobs/<sha256>`, gzip, dedup, `delete[]`); `vdlu-keygen` / `vdlu-sign` (ed25519); o `vdlu-gc` poda blobs órfãos por referência aos últimos N manifestos (fail-safe, dry-run por padrão).
- **Motor (aparelho):** POSIX sh, sem `jq`. O `update.sh` (`check | run | resume | boot | status | cancel`) roda DIFF -> FETCH -> APPLY -> COMMIT como uma **transação retomável** (journal), com rollback e um lock de `mkdir`. A assinatura é verificada pelo `ed25519-mini` embarcado (sem `openssl` no aparelho).
- **WebUI:** um painel de Updates plug-and-play (toast de progresso, cancelar, banner de reboot), JS puro.

## Perfis

- `trusted`: uso privado, fonte `file://` ou SSH, verificação best-effort (hash sempre).
- `hardened`: uso público, **assinatura obrigatória**, downgrade bloqueado. O manifesto é **vinculado ao id do módulo**, e todo campo é validado fail-closed antes de qualquer download.

## Adote no seu módulo

Vendorize `engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` em `<module>/vdlu/`, embarque sua **chave pública raw de 32 bytes** como `vdlu/keyring/<id>.pub`, adicione um `config` (perfil + fonte), fie os gatilhos (`post-fs-data.sh` pré-zygote para autoatualização no boot; um gatilho de abertura da WebUI) e adicione `vdlu-pack` + `vdlu-sign` ao seu release. Veja [`docs/QUICKSTART.md`](docs/QUICKSTART.md) para um template pronto.

## Segurança

- **Todo campo do manifesto é input hostil.** O `validate_plan()` rejeita o manifesto inteiro fail-closed se houver um path absoluto ou com `..`, um `sha256` que não tenha 64 caracteres hex, ou um mode / classe / encoding inválido, **antes** de qualquer fetch ou apply.
- A **chave privada de assinatura nunca toca a CI nem um aparelho**; apenas a chave pública raw é embarcada, e a verificação usa `ed25519-mini`, não `openssl`.
- O `hardened` é fail-closed por inversão: qualquer coisa diferente do literal `trusted` é tratada como `hardened`, então um valor de perfil corrompido nunca pode aceitar silenciosamente um manifesto não assinado.
- Arquivos da classe reboot (`.so`, overlay de `/system`, `sepolicy.rule`) são **encenados, nunca escritos por cima de um inode vivo**; todo o resto se aplica ao vivo. Um apply que falha aborta em vez de sobrescrever sem um backup.

## Build / teste

São scripts, nada a compilar. Ponta a ponta (produtor + motor juntos):

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # então run / boot
```

`sh -n engine/*.sh`, `node --check webui/vdlu.js`, e abra `webui/demo.html` em um navegador (ele mocka a ponte com o aparelho).

## Documentação

- [`INTERFACES.md`](docs/INTERFACES.md): o contrato de costura entre os componentes (a lei da convergência; trate-o como imutável).
- [`ENGINE.md`](docs/ENGINE.md): o engine do lado do dispositivo (`update.sh`): a transação retomável DIFF -> FETCH -> APPLY -> COMMIT.
- [`PRODUCER.md`](docs/PRODUCER.md): o lado do PC/release: construir e assinar o feed endereçado por conteúdo (`vdlu-pack`, `vdlu-sign`).
- [`WEBUI.md`](docs/WEBUI.md): o widget encaixável do painel Updates (toast de progresso, cancelar, banner de reboot).
- [`docs/QUICKSTART.md`](docs/QUICKSTART.md): um guia de adoção passo a passo e snippets de fiação.

## Veja também

Projetos irmãos do mesmo autor:

- **[VDBackup](https://github.com/VD171/VD-Backup)**: backup e restauração completos de apps e dados como root, conduzidos inteiramente por uma WebUI.
- **[COPG-VD](https://github.com/VD171/COPG-VD)**: um spoofer de aparelho que transforma um fingerprint novo em um perfil coerente e consistente.
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: um daemon SSH rooteado, standalone e configurável, para KernelSU/APatch/Magisk.
- **[VDInfos](https://github.com/VD171/VD-Infos)**: um debugger de métodos de aparelho que lê cada item por todos os métodos capazes de lê-lo.
- **[VDGoogle](https://github.com/VD171/VD-Google)**: lê o que o Google registra no seu aparelho, totalmente no aparelho e sem internet.

## Contatos

- https://vd171.ru
- https://vd.priv8.ru
- **Telegram:** @VD_Priv8 https://t.me/VD_Priv8
- **Channel:** @Priv8_VD https://t.me/Priv8_VD
- **Discord:** @VD.Priv8 https://discord.com/users/1296831918989639721
- **E-mail:** vd.priv8@pm.me
- **XDA-Developers:** @VD171 https://xdaforums.com/m/vd171.4699873/
- **GitHub:** @VD171 https://github.com/VD171

## Licença

O código próprio do VDLiveUpdate é **Apache-2.0**; veja [LICENSE](LICENSE). Ele vendoriza um pequeno verificador
`ed25519-mini` e um `curl` estático para o bootstrap do fetch, cada um sob sua própria licença; veja
[NOTICE.md](NOTICE.md) e os arquivos `PROVENANCE.json` ao lado dos binários incluídos.

## Marcas registradas

O VDLiveUpdate é um projeto independente e não oficial, sem afiliação ou endosso de terceiros.
"Android" é uma marca registrada da Google LLC; "KernelSU", "Magisk" e "APatch" são marcas de seus
respectivos autores. O VDLU roda inteiramente no seu aparelho e no seu próprio host de release.

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`

---

📣 **Join the channel for updates:** @Priv8_VD https://t.me/Priv8_VD
