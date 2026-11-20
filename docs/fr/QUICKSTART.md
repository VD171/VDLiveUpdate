> **Languages:** [English](../QUICKSTART.md) · [العربية](../ar/QUICKSTART.md) · [Čeština](../cs/QUICKSTART.md) · [Deutsch](../de/QUICKSTART.md) · [Español](../es/QUICKSTART.md) · [فارسی](../fa/QUICKSTART.md) · Français · [हिन्दी](../hi/QUICKSTART.md) · [Bahasa Indonesia](../id/QUICKSTART.md) · [Italiano](../it/QUICKSTART.md) · [日本語](../ja/QUICKSTART.md) · [한국어](../ko/QUICKSTART.md) · [Nederlands](../nl/QUICKSTART.md) · [Polski](../pl/QUICKSTART.md) · [Português](../pt/QUICKSTART.md) · [Русский](../ru/QUICKSTART.md) · [Svenska](../sv/QUICKSTART.md) · [ไทย](../th/QUICKSTART.md) · [Türkçe](../tr/QUICKSTART.md) · [Українська](../uk/QUICKSTART.md) · [Tiếng Việt](../vi/QUICKSTART.md) · [中文](../zh/QUICKSTART.md)

---

# Quickstart d'adoption de VDLU

Une checklist copier-coller pour vendorer **VDLiveUpdate** dans un module. VDLU n'est pas un
module en soi : il est déposé dans `<module>/vdlu/` et voyage dans le zip de ton module.
Pour le rationale complet voir [`INTERFACES.md`](INTERFACES.md) (le contrat de couture),
[`ENGINE.md`](ENGINE.md), [`PRODUCER.md`](PRODUCER.md) et [`WEBUI.md`](WEBUI.md).

Remplace `<id>` par l'id de ta clé de signature, `<abi>` par la ou les ABI d'appareil que tu livres
(`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), et `<module>` par ton arbre de module.

## Layout cible

Voici l'arbre `vdlu/` exact que le module porte après l'adoption :

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

L'état mutable de l'engine (`config`, `current.json`, journal, lock) vit en
Tier-2, `/data/adb/<modid>/vdlu/`, hors du dir du module ; `config.default` l'amorce
au premier run.

## 1. Vendorer l'engine

Copie l'engine, le verify shim et le vérificateur par-ABI dans `<module>/vdlu/` :

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh      <module>/vdlu/update.sh
cp engine/vdlu-verify    <module>/vdlu/vdlu-verify
cp -r verify/<abi>       <module>/vdlu/verify/<abi>      # ed25519-mini per ABI
```

Ne livre que les ABI que tu supportes ; `customize.sh` peut élaguer `verify/` à l'ABI de
l'appareil au moment de l'installation.

## 2. Générer une clé de signature (une fois)

```sh
producer/vdlu-keygen <id> ./keys
```

Cela émet `<id>.pem` (privée, garde-la hors de tout appareil et de tout push vers un repo),
`<id>.pub` (PEM, côté PC uniquement) et `<id>.pub.raw` (RAW de 32 octets, pour le keyring de l'appareil).

## 3. Embarquer la clé publique raw

Le keyring de l'appareil tient la clé **RAW de 32 octets**, jamais le PEM (`ed25519-mini`
ne peut pas lire un PEM) :

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

Le keyring est stable entre les releases (il ne change qu'à la rotation de clé) : lors d'un
re-vendor, **vérifie, n'écrase pas**.

## 4. Écrire la config

Livre `config.default` dans `<module>/vdlu/` (amorce le `config` Tier-2 au premier run) :

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

N'utilise `profile=trusted` que pour une source privée `file://`/SSH (verify best-effort ;
le sha256 de chaque blob est quand même vérifié). Toute valeur autre que le littéral `trusted`
est traitée comme `hardened` (fail-closed).

## 5. Câbler les triggers

**Au reboot** (`auto_on_reboot`) : appelle l'engine pre-zygote depuis `post-fs-data.sh`
pour que les fichiers stagés (un `.so`, un overlay `/system`, un `sepolicy.rule`) entrent sans
reboot supplémentaire :

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**À l'ouverture de la WebUI** (`auto_on_webui_open`) : câble le panneau Updates drop-in dans ton
`webroot/index.html` :

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

(`vdlu.js` / `vdlu.css` sont vendorés depuis `webui/` ; une traduction peut être ajoutée avec
`i18n: window.VDLU_I18N_<LANG>`.)

## 6. Signer le feed dans ton workflow de release

À chaque release, empaquette l'arbre final du module et signe le manifeste. Garde la clé privée
sur la machine de l'opérateur, jamais dans la CI :

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]        # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

## 7. Livrer le baseline

Génère `baseline.json` sur l'arbre livré et place-le à `<module>/vdlu/baseline.json`.
Il amorce `current.json` à une installation fraîche pour que l'appareil naisse "à jour" (sans
re-fetch). C'est une **semence locale de confiance** : sans signature et sans clé, donc la CI peut la construire
sans jamais toucher la clé de signature :

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Non fatal s'il est absent (l'appareil part simplement de `0` à la première mise à jour).

---

Voilà toute l'adoption. `sh -n <module>/vdlu/update.sh` doit passer ; teste le
producer et l'engine de bout en bout comme montré dans [`PRODUCER.md`](PRODUCER.md) et le
README racine avant de livrer.

<!-- doc-footer -->

---

> _Cette documentation a été générée avec Claude (Anthropic) et est maintenue par VD171. Les corrections et améliorations sont les bienvenues ; voir [CONTRIBUTING.md](CONTRIBUTING.md)._
