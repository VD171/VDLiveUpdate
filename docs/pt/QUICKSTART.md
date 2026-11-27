> **Languages:** [English](../QUICKSTART.md) · [العربية](../ar/QUICKSTART.md) · [Čeština](../cs/QUICKSTART.md) · [Deutsch](../de/QUICKSTART.md) · [Español](../es/QUICKSTART.md) · [فارسی](../fa/QUICKSTART.md) · [Français](../fr/QUICKSTART.md) · [हिन्दी](../hi/QUICKSTART.md) · [Bahasa Indonesia](../id/QUICKSTART.md) · [Italiano](../it/QUICKSTART.md) · [日本語](../ja/QUICKSTART.md) · [한국어](../ko/QUICKSTART.md) · [Nederlands](../nl/QUICKSTART.md) · [Polski](../pl/QUICKSTART.md) · Português · [Русский](../ru/QUICKSTART.md) · [Svenska](../sv/QUICKSTART.md) · [ไทย](../th/QUICKSTART.md) · [Türkçe](../tr/QUICKSTART.md) · [Українська](../uk/QUICKSTART.md) · [Tiếng Việt](../vi/QUICKSTART.md) · [中文](../zh/QUICKSTART.md)

---

# Quickstart de adoção do VDLU

Um checklist copia-e-cola para vendorizar o **VDLiveUpdate** num módulo. O VDLU não é um
módulo em si: é largado em `<module>/vdlu/` e vai dentro do zip do seu módulo. Para o
rationale completo veja [`INTERFACES.md`](INTERFACES.md) (o contrato de costura),
[`ENGINE.md`](ENGINE.md), [`PRODUCER.md`](PRODUCER.md) e [`WEBUI.md`](WEBUI.md).

Substitua `<id>` pelo id da sua chave de assinatura, `<abi>` pela(s) ABI(s) do device que
você entrega (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), e `<module>` pela árvore do seu
módulo.

## Layout alvo

Esta é a árvore `vdlu/` exata que o módulo carrega após a adoção:

```
<module>/
├── module.prop
├── post-fs-data.sh            # pre-zygote trigger: sh "$MODDIR/vdlu/update.sh" boot
├── webroot/
│   └── index.html             # your WebUI, wiring the Updates panel (step 5)
└── vdlu/
    ├── update.sh              # the engine (vendored byte-for-byte)
    ├── vdlu-verify            # ed25519 verify shim (device-side, no openssl)
    ├── verify/
    │   └── <abi>/ed25519-mini # per-ABI verifier binary
    ├── keyring/
    │   └── <id>.pub           # RAW 32-byte public key (NEVER the PEM)
    ├── config.default         # profile + source + automation defaults
    └── baseline.json          # install seed (unsigned, keyless)
```

O estado mutável do engine (`config`, `current.json`, journal, lock) vive em
Tier-2, `/data/adb/<modid>/vdlu/`, fora do dir do módulo, `config.default` o semeia
na primeira execução.

## 1. Vendorize o engine

Copie o engine, o shim de verify e o verificador por-ABI para `<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh      <module>/vdlu/update.sh
cp engine/vdlu-verify    <module>/vdlu/vdlu-verify
cp -r verify/<abi>       <module>/vdlu/verify/<abi>      # ed25519-mini per ABI
```

Entregue só as ABIs que você suporta, `customize.sh` pode podar `verify/` para a ABI do
device no tempo de instalação.

## 2. Gere uma chave de assinatura (uma vez)

```sh
producer/vdlu-keygen <id> ./keys
```

Isso emite `<id>.pem` (privada, mantenha-a fora de todo device e de todo push de repo),
`<id>.pub` (PEM, só PC-side) e `<id>.pub.raw` (RAW 32 bytes, para o keyring do device).

## 3. Embarque a chave pública crua

O keyring do device guarda a chave **RAW de 32 bytes**, nunca o PEM (`ed25519-mini`
não consegue ler um PEM):

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

O keyring é estável entre releases (só muda em rotação de chave): num
re-vendor, **verifique, não sobrescreva**.

## 4. Escreva a config

Entregue `config.default` em `<module>/vdlu/` (semeia o `config` em Tier-2 na primeira execução):

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
# apply_busy_file=/data/adb/<modid>/.busy   # OPT-IN: defer APPLY while this path exists (e.g. a running backup)
```

Use `profile=trusted` só para uma fonte privada `file://`/SSH (verify best-effort;
o sha256 de todo blob ainda é conferido). Qualquer valor que não seja o literal `trusted`
é tratado como `hardened` (fail-closed).

## 5. Fie os gatilhos

**No reboot** (`auto_on_reboot`): chame o engine pre-zygote a partir do `post-fs-data.sh`
para que arquivos staged (uma `.so`, um overlay de `/system`, um `sepolicy.rule`) troquem
sem reboot extra:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**Na abertura da WebUI** (`auto_on_webui_open`): fie o painel de Updates drop-in no seu
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
  VDLU.onWebUIOpen();                                             // evaluates journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // the "Updates" tab
</script>
```

(`vdlu.js` / `vdlu.css` são vendorizados de `webui/`, uma tradução pode ser adicionada com
`i18n: window.VDLU_I18N_<LANG>`.)

## 6. Assine o feed no seu workflow de release

A cada release, empacote a árvore final do módulo e assine o manifesto. Mantenha a chave
privada na máquina do operador, nunca no CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]        # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

## 7. Entregue a baseline

Gere `baseline.json` sobre a árvore entregue e coloque-a em `<module>/vdlu/baseline.json`.
Ela semeia `current.json` numa instalação limpa para que o device nasça "atualizado" (sem
re-fetch). É uma **semente local confiável**: não-assinada e sem chave, então o CI pode
construí-la sem jamais tocar na chave de assinatura:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Não é fatal se ausente (o device só começa de `0` na primeira atualização).

---

Essa é a adoção inteira. `sh -n <module>/vdlu/update.sh` deve passar, teste o
producer e o engine ponta a ponta como mostrado em [`PRODUCER.md`](PRODUCER.md) e no
README raiz antes de entregar.

<!-- doc-footer -->

---

> _Esta documentação foi gerada com o Claude (Anthropic) e é mantida por VD171. Correções e melhorias são bem-vindas, veja [CONTRIBUTING.md](CONTRIBUTING.md)._
