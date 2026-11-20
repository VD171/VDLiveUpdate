# Quick Start

Este é o checklist de adoção: como vendorizar o **VDLiveUpdate (VDLU)** em um
módulo KernelSU / APatch / Magisk. O VDLU não é um módulo em si. Ele é colocado em
`<module>/vdlu/` e vem dentro do zip do seu módulo, de modo que um módulo instalado
pode se atualizar de forma flashless a partir de um feed assinado que você publica.

Ao longo do texto, substitua `<id>` pelo id da sua chave de assinatura, `<abi>` pela(s)
ABI(s) de dispositivo que você envia (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), e `<module>`
pela sua árvore de módulo.

Para o racional por trás de cada peça, veja [[Engine]], [[Producer]], [[WebUI]] e
[[Security and Trust Model]].

## O layout `vdlu/` dentro do módulo

Esta é a árvore exata que seu módulo carrega após a adoção:

```
<module>/
|-- module.prop
|-- post-fs-data.sh            # pre-zygote trigger: sh "$MODDIR/vdlu/update.sh" boot
|-- webroot/
|   `-- index.html             # your WebUI, wiring the Updates panel (step 5)
`-- vdlu/
    |-- update.sh              # the engine (vendored byte-for-byte)
    |-- vdlu-verify            # ed25519 verify shim (device-side, no openssl)
    |-- verify/
    |   `-- <abi>/ed25519-mini # per-ABI verifier binary
    |-- keyring/
    |   `-- <id>.pub           # RAW 32-byte public key (NEVER the PEM)
    |-- config.default         # profile + source + automation defaults
    `-- baseline.json          # install seed (unsigned, keyless)
```

O estado mutável do motor (`config`, `current.json`, journal, lock, cache de blobs)
vive no Tier-2 em `/data/adb/<modid>/vdlu/`, fora do diretório do módulo.
`config.default` semeia esse `config` do Tier-2 na primeira execução. Veja [[Engine]] para o
layout de estado completo.

## 1. Vendorizar o motor

Copie o motor, o shim de verify e o binário verificador por ABI para
`<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh   <module>/vdlu/update.sh
cp engine/vdlu-verify <module>/vdlu/vdlu-verify
cp -r verify/<abi>    <module>/vdlu/verify/<abi>    # ed25519-mini per ABI
```

Envie apenas as ABIs que você suporta. Seu `customize.sh` pode podar `verify/` até
a ABI do dispositivo no momento da instalação.

## 2. Gerar uma chave de assinatura (uma vez)

```sh
producer/vdlu-keygen <id> ./keys
```

Isso emite três arquivos:

- `<id>.pem` - a chave privada. Mantenha-a fora de todo dispositivo e fora de qualquer
  push de repo ou secret de CI.
- `<id>.pub` - a chave pública PEM. Apenas do lado do PC (usada por `vdlu-sign`).
- `<id>.pub.raw` - a chave pública RAW de 32 bytes, para o keyring do dispositivo.

Veja [[Security and Trust Model]] para por que a divisão importa.

## 3. Embarcar a chave pública bruta

O keyring do dispositivo guarda a chave **RAW de 32 bytes**, nunca o PEM. O `ed25519-mini`
não consegue ler um PEM, então copiar o PEM aqui quebra a verificação no dispositivo:

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

O keyring é estável entre releases: ele só muda em rotação de chave. Em uma
re-vendorização, **verifique-o, não o sobrescreva**.

## 4. Escrever a config

Envie `config.default` em `<module>/vdlu/`. Ele semeia o `config` do Tier-2 na primeira
execução:

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

Use `profile=trusted` apenas para uma fonte privada `file://` ou SSH (verify é
best-effort ali, mas o sha256 de todo blob ainda é conferido). Qualquer valor diferente
do literal `trusted` é tratado como `hardened`, fail-closed. Veja
[[Security and Trust Model]] para a semântica completa de perfil.

## 5. Ligar os gatilhos

**On reboot** (`auto_on_reboot`): chame o motor pré-zygote a partir de
`post-fs-data.sh`, para que arquivos de classe reboot estagiados (um `.so`, um overlay de `/system`,
um `sepolicy.rule`) troquem sem reinício extra:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**On WebUI open** (`auto_on_webui_open`): ligue o painel de Updates drop-in no seu
`webroot/index.html`:

```html
<link rel="stylesheet" href="vdlu.css">
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,
    vdluDir:   '/data/adb/' + MODID + '/vdlu',
    modid:     MODID,
    module:    'YourModule'
  });
  VDLU.onWebUIOpen();                                            // journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // the "Updates" tab
</script>
```

`vdlu.js` e `vdlu.css` são vendorizados de `webui/`. Uma tradução pode ser adicionada
com `i18n: window.VDLU_I18N_<LANG>`. Veja [[WebUI]] para o contrato do painel.

## 6. Assinar o feed no seu workflow de release

A cada release, empacote a árvore final do módulo e assine o manifesto. Mantenha a chave
privada na máquina do operador, nunca no CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> \
                    --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

`vdlu-pack` é endereçado por conteúdo e deduplicante, então a publicação é incremental:
blobs inalterados nunca são reenviados. Veja [[Producer]] e [[Feed Format]].

## 7. Enviar a baseline

Gere `baseline.json` sobre a árvore enviada e coloque-a em
`<module>/vdlu/baseline.json`. Ela semeia `current.json` em uma instalação nova, de modo que o
dispositivo nasce "atual" e não faz re-fetch de sua própria versão enviada. Ela é um
**seed local confiável**: não assinado e sem chave, de modo que o CI pode construí-la sem nunca
tocar a chave de assinatura:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

É não fatal se ausente: o dispositivo simplesmente parte da versão `0` na
primeira atualização.

---

Essa é toda a adoção. Antes de enviar, `sh -n <module>/vdlu/update.sh`
deve passar, e você deve testar o producer e o motor de ponta a ponta como mostrado em
[[Contributing]] e [[Producer]].
