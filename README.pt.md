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

# VD Live Update

> **Languages:** [English](README.md) · [العربية](README.ar.md) · [Čeština](README.cs.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [فارسی](README.fa.md) · [Français](README.fr.md) · [हिन्दी](README.hi.md) · [Bahasa Indonesia](README.id.md) · [Italiano](README.it.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · Português · [Русский](README.ru.md) · [Svenska](README.sv.md) · [ไทย](README.th.md) · [Türkçe](README.tr.md) · [Українська](README.uk.md) · [Tiếng Việt](README.vi.md) · [中文](README.zh.md)

<p align="center">
  <img src="images/logo-wordmark.png" alt="VD Live Update" width="320">
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-1a7f37" alt="License"></a>
  <a href="https://github.com/VD171/VDLiveUpdate/stargazers"><img src="https://img.shields.io/github/stars/VD171/VDLiveUpdate?color=d29922" alt="Stars"></a>
</p>

<p align="center">
  <a href="docs/QUICKSTART.md">Quickstart</a> ·
  <a href="docs/ENGINE.md">Engine</a> ·
  <a href="docs/PRODUCER.md">Producer</a> ·
  <a href="docs/WEBUI.md">WebUI</a> ·
  <a href="docs/INTERFACES.md">Interfaces</a> ·
  <a href="docs/AI-AGENTS.md">AI agents</a> ·
  <a href="docs/TRUST-MODEL.md">Trust model</a>
</p>

O **VDLU** é um motor de autoatualização incremental e sem flash para módulos **KernelSU / APatch / Magisk**. Um módulo instalado se atualiza sozinho baixando **apenas os arquivos que mudaram** (blobs endereçados por conteúdo + um manifesto assinado), aplica os que são aplicáveis ao vivo **sem reboot** e encena e sinaliza os poucos que realmente precisam de um (um `.so`, um overlay de `/system`, uma `sepolicy.rule`). Sem gerenciador de root, sem rebaixar o `.zip` inteiro, sem reboot a não ser pelos arquivos encenados.

Ele foi feito para ser **vendorizado** dentro de um módulo (copiado para `<module>/vdlu/`), e não para rodar como um módulo em si.

## Por quê

Uma atualização normal de módulo entrega o `.zip` inteiro de novo. Para um módulo grande, isso significa um rebaixamento enorme por causa de poucas linhas alteradas, e um manifesto de atualização estático só consegue apontar para um `zipUrl`, então não consegue servir o flavor (ABI, full vs lite) que o aparelho realmente tem. O VDLU compara a árvore **instalada** com um feed assinado e baixa apenas os deltas, então um install arm64-full continua arm64-full, um install lite continua lite, e a maioria das atualizações se aplica ao vivo.

## Como funciona

- **Produtor (PC / release):** o `vdlu-pack` transforma a árvore de um módulo em um feed endereçado por conteúdo (`manifest.json` + `blobs/<sha256>`, gzip, dedup, `delete[]`), `vdlu-keygen` / `vdlu-sign` (ed25519), o `vdlu-gc` poda blobs órfãos por referência aos últimos N manifestos (fail-safe, dry-run por padrão).
- **Motor (aparelho):** POSIX sh, sem `jq`. O `update.sh` (`check | run | resume | boot | status | cancel`) roda DIFF -> FETCH -> APPLY -> COMMIT como uma **transação retomável** (journal), com rollback e um lock de `mkdir`. A assinatura é verificada pelo `ed25519-mini` embarcado (sem `openssl` no aparelho).
- **WebUI:** um painel de Updates plug-and-play (toast de progresso, cancelar, banner de reboot), JS puro.

## Perfis

- `trusted`: uso privado, fonte `file://` ou SSH, verificação best-effort (hash sempre).
- `hardened`: uso público, **assinatura obrigatória**, downgrade bloqueado. O manifesto é **vinculado ao id do módulo**, e todo campo é validado fail-closed antes de qualquer download.

## Adote no seu módulo

Vendorize `engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` em `<module>/vdlu/`, embarque sua **chave pública raw de 32 bytes** como `vdlu/keyring/<id>.pub`, adicione um `config` (perfil + fonte), fie os gatilhos (`post-fs-data.sh` pré-zygote para autoatualização no boot, um gatilho de abertura da WebUI) e adicione `vdlu-pack` + `vdlu-sign` ao seu release. Veja [`docs/QUICKSTART.md`](docs/QUICKSTART.md) para um template pronto.

## Segurança

- **Todo campo do manifesto é input hostil.** O `validate_plan()` rejeita o manifesto inteiro fail-closed se houver um path absoluto ou com `..`, um `sha256` que não tenha 64 caracteres hex, ou um mode / classe / encoding inválido, **antes** de qualquer fetch ou apply.
- A **chave privada de assinatura nunca toca a CI nem um aparelho**, apenas a chave pública raw é embarcada, e a verificação usa `ed25519-mini`, não `openssl`.
- O `hardened` é fail-closed por inversão: qualquer coisa diferente do literal `trusted` é tratada como `hardened`, então um valor de perfil corrompido nunca pode aceitar silenciosamente um manifesto não assinado.
- Arquivos da classe reboot (`.so`, overlay de `/system`, `sepolicy.rule`) são **encenados, nunca escritos por cima de um inode vivo**, todo o resto se aplica ao vivo. Um apply que falha aborta em vez de sobrescrever sem um backup.

## Build / teste

São scripts, nada a compilar. Ponta a ponta (produtor + motor juntos):

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # então run / boot
```

`sh -n engine/*.sh`, `node --check webui/vdlu.js`, e abra `webui/demo.html` em um navegador (ele mocka a ponte com o aparelho).

## Agentes de IA

O engine é controlado inteiramente pela shell (`sh engine/update.sh <check|run|resume|boot|status|cancel>` imprime um status legível por máquina), então um agente de IA pode verificar, aplicar e retomar uma atualização sem interface. O contrato de costura entre os componentes está em [`docs/INTERFACES.md`](docs/INTERFACES.md), e patches de IA passam pelo mesmo nível de revisão que qualquer outro.

## Documentação

- [`INTERFACES.md`](docs/INTERFACES.md): o contrato de costura entre os componentes (a lei da convergência, trate-o como imutável).
- [`ENGINE.md`](docs/ENGINE.md): o engine do lado do dispositivo (`update.sh`): a transação retomável DIFF -> FETCH -> APPLY -> COMMIT.
- [`PRODUCER.md`](docs/PRODUCER.md): o lado do PC/release: construir e assinar o feed endereçado por conteúdo (`vdlu-pack`, `vdlu-sign`).
- [`WEBUI.md`](docs/WEBUI.md): o widget encaixável do painel Updates (toast de progresso, cancelar, banner de reboot).
- [`docs/QUICKSTART.md`](docs/QUICKSTART.md): um guia de adoção passo a passo e snippets de fiação.

## Veja também

- **[COPG-VD](https://github.com/VD171/COPG-VD)**: spoofing do fingerprint global do dispositivo / Play Integrity, no dispositivo inteiro com escopo por app e uma WebUI.
- **[VDBackup](https://github.com/VD171/VD-Backup)**: backup e restauração completos de apps e dados como root, conduzidos inteiramente por uma WebUI.
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: um daemon SSH independente com root (Dropbear).
- **[VDGoogle](https://github.com/VD171/VD-Google)**: seus serviços Google (RCS, Wallet, atestações do Play Integrity), lidos no seu dispositivo sem internet.
- **[VDInstaller](https://github.com/VD171/VD-Installer)**: um instalador sideload com root e sem atrito para APKs únicos, em lote e divididos, com um interruptor para o verificador do Play Protect e falsificação da origem de instalação.
- **[VDInfos](https://github.com/VD171/VD-Infos)**: um depurador de métodos do dispositivo: lê cada item por todos os métodos que conseguem lê-lo e os compara lado a lado.
- **[VD-Modules](https://github.com/VD171/VD-Modules)**: nosso repositório de módulos para MMRL/WebUI-X (instale todos estes pelo seu gerenciador root).
- **[@VictorGabriel7Dev/build.prop](https://github.com/VictorGabriel7Dev/build.prop)**: um conjunto de dados de fingerprints `build.prop` de Pixel (fork de @T3SL4).
- **[@VictorGabriel7Dev/mtproto-store](https://github.com/VictorGabriel7Dev/mtproto-store)**: use o Telegram como um object store a partir de uma pequena CLI em Go.

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

O código próprio do VDLiveUpdate é **Apache-2.0**, veja [LICENSE](LICENSE). Ele vendoriza um pequeno verificador
`ed25519-mini` e um `curl` estático para o bootstrap do fetch, cada um sob sua própria licença, veja
[NOTICE.md](NOTICE.md) e os arquivos `PROVENANCE.json` ao lado dos binários incluídos.

## Marcas registradas

O VDLiveUpdate é um projeto independente e não oficial, sem afiliação ou endosso de terceiros.
"Android" é uma marca registrada da Google LLC, "KernelSU", "Magisk" e "APatch" são marcas de seus
respectivos autores. O VDLU roda inteiramente no seu aparelho e no seu próprio host de release.

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`

---

📣 **Entre no canal para receber atualizações:** @Priv8_VD https://t.me/Priv8_VD
