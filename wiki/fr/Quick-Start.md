# Quick Start

Ceci est la liste de vérification d'adoption : comment intégrer **VDLiveUpdate (VDLU)** dans un
module KernelSU / APatch / Magisk. VDLU n'est pas un module en soi. Il se dépose dans
`<module>/vdlu/` et se livre à l'intérieur du zip de votre module, de sorte qu'un module installé puisse
se mettre à jour sans flashage depuis un feed signé que vous publiez.

Partout, remplacez `<id>` par l'id de votre clé de signature, `<abi>` par la ou les
ABI de l'appareil que vous livrez (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), et `<module>`
par l'arborescence de votre module.

Pour la justification de chaque pièce, voir [[Engine]], [[Producer]], [[WebUI]] et
[[Security and Trust Model]].

## La disposition `vdlu/` dans le module

Voici l'arborescence exacte que votre module porte après adoption :

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

L'état mutable du moteur (`config`, `current.json`, journal, verrou, cache de blobs)
vit en Tier-2 dans `/data/adb/<modid>/vdlu/`, hors du répertoire du module.
`config.default` amorce ce `config` Tier-2 à la première exécution. Voir [[Engine]] pour la
disposition d'état complète.

## 1. Intégrer le moteur

Copiez le moteur, le shim de vérification et le binaire vérificateur par ABI dans
`<module>/vdlu/` :

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh   <module>/vdlu/update.sh
cp engine/vdlu-verify <module>/vdlu/vdlu-verify
cp -r verify/<abi>    <module>/vdlu/verify/<abi>    # ed25519-mini per ABI
```

Ne livrez que les ABI que vous supportez. Votre `customize.sh` peut élaguer `verify/` jusqu'à
l'ABI de l'appareil au moment de l'installation.

## 2. Générer une clé de signature (ponctuel)

```sh
producer/vdlu-keygen <id> ./keys
```

Cela émet trois fichiers :

- `<id>.pem` - la clé privée. Gardez-la hors de tout appareil et hors de tout push de dépôt
  ou secret de CI.
- `<id>.pub` - la clé publique PEM. Côté PC uniquement (utilisée par `vdlu-sign`).
- `<id>.pub.raw` - la clé publique de 32 octets BRUTS, pour le keyring de l'appareil.

Voir [[Security and Trust Model]] pour comprendre pourquoi la séparation compte.

## 3. Embarquer la clé publique brute

Le keyring de l'appareil contient la clé de **32 octets BRUTS**, jamais le PEM. `ed25519-mini`
ne peut pas lire un PEM, de sorte que copier le PEM ici casse la vérification sur l'appareil :

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

Le keyring est stable d'une release à l'autre : il ne change que lors d'une rotation de clé. À une
ré-intégration, **vérifiez-le, ne l'écrasez pas**.

## 4. Écrire la config

Livrez `config.default` dans `<module>/vdlu/`. Il amorce le `config` Tier-2 à la première
exécution :

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

Utilisez `profile=trusted` uniquement pour une source privée `file://` ou SSH (la vérification est
au mieux là-bas, mais le sha256 de chaque blob est quand même vérifié). Toute valeur autre
que le littéral `trusted` est traitée comme `hardened`, fail-closed. Voir
[[Security and Trust Model]] pour la sémantique complète des profils.

## 5. Brancher les déclencheurs

**Au redémarrage** (`auto_on_reboot`) : appelez le moteur en pré-zygote depuis
`post-fs-data.sh`, de sorte que les fichiers de classe reboot échelonnés (un `.so`, un overlay `/system`,
un `sepolicy.rule`) soient échangés sans redémarrage supplémentaire :

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**À l'ouverture de la WebUI** (`auto_on_webui_open`) : branchez le panneau Updates prêt à insérer dans votre
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
  VDLU.onWebUIOpen();                                            // journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // the "Updates" tab
</script>
```

`vdlu.js` et `vdlu.css` sont intégrés depuis `webui/`. Une traduction peut être ajoutée
avec `i18n: window.VDLU_I18N_<LANG>`. Voir [[WebUI]] pour le contrat du panneau.

## 6. Signer le feed dans votre flux de publication

À chaque release, packez l'arborescence finale du module et signez le manifeste. Gardez la clé privée
sur la machine de l'opérateur, jamais en CI :

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> \
                    --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

`vdlu-pack` est adressé par contenu et déduplique, de sorte que la publication est incrémentale :
les blobs inchangés ne sont jamais repoussés. Voir [[Producer]] et [[Feed Format]].

## 7. Livrer la baseline

Générez `baseline.json` sur l'arborescence livrée et placez-le à
`<module>/vdlu/baseline.json`. Il amorce `current.json` à une installation neuve, de sorte que
l'appareil naît "à jour" et ne retélécharge pas sa propre version livrée. C'est une
**semence locale de confiance** : non signée et sans clé, de sorte que la CI puisse la construire sans jamais
toucher la clé de signature :

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Elle est non fatale si absente : l'appareil part simplement de la version `0` à la
première mise à jour.

---

Voilà toute l'adoption. Avant de livrer, `sh -n <module>/vdlu/update.sh`
doit passer, et vous devriez tester le producteur et le moteur de bout en bout comme montré dans
[[Contributing]] et [[Producer]].
