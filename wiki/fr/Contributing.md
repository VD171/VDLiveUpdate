# Contributing

Les contributions sont les bienvenues. VDLU est un moteur de mise à jour automatique, incrémental et sans flashage
intégré dans les modules KernelSU / APatch / Magisk. Cette page est le flux de travail de développement
pratique ; pour comprendre comment les pièces s'imbriquent, lisez d'abord [[Architecture]], [[Engine]] et
[[Producer]].

## Rien ne compile

VDLU, ce sont des scripts (`sh` POSIX, un peu de Python du côté publication, du JS vanilla pour la
WebUI), de sorte qu'il n'y a pas d'étape de build. Vous vérifiez un changement en exécutant le pipeline
de bout en bout et en vérifiant statiquement chaque pièce.

## Le contrat de couture d'abord

Le contrat d'interface entre les composants (les signatures de CLI, les noms de fichiers et
les clés JSON partagés par le moteur, le producteur et la WebUI) est la **loi de
convergence**. Traitez-le comme immuable. Si votre changement touche la
couture producteur-vers-moteur (schéma de manifeste, schéma de journal, clés de config, la
règle de signature/canonicalisation), **alignez d'abord le contrat d'interface**, puis
changez le code des deux côtés pour qu'il concorde. Un changement d'un côté de la couture sans
l'autre casse silencieusement les adoptants. Voir [[Producer]] pour la règle de canonicalisation
sur laquelle le signataire et le vérificateur doivent concorder octet pour octet.

## Tester de bout en bout avant un PR

Exécutez le producteur et le moteur ensemble sur une arborescence jetable, de la même façon que
la publication d'un adoptant le fait :

```sh
# 1. a signing key
producer/vdlu-keygen demo /tmp/k

# 2. pack a module tree into a feed
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1

# 3. sign the manifest in place
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo

# 4. verify the manifest the way the device will (RAW 32B keyring)
engine/vdlu-verify /tmp/feed/manifest.json /tmp/keyring

# 5. drive the engine against the feed (source=file:///tmp/feed in the config)
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

Puis vérifiez statiquement chaque composant :

```sh
sh -n engine/*.sh            # POSIX sh syntax, must pass
node --check webui/vdlu.js   # WebUI JS syntax
```

Et ouvrez `webui/demo.html` dans un navigateur : il simule le pont du gestionnaire root
(`ksu.exec`), de sorte que vous puissiez exercer le panneau Updates, le toast de progression, l'annulation
et la bannière de redémarrage sans appareil. Voir [[WebUI]].

## Règles de la maison

- **`sh` POSIX sur l'appareil.** Pas de bashismes au-delà de `local`, et pas de `jq`. Il doit
  tourner sur toybox / busybox.
- **La sécurité est non négociable.** Chaque champ du manifeste est une entrée hostile ;
  `validate_plan()` reste fail-closed, et la clé de signature privée ne touche jamais
  la CI ni un appareil. Ne relâchez pas une vérification pour faire passer un test.
- **Rigueur à l'échec.** Gardez la transaction reprenable : rien ne rapporte "done"
  sans un re-hachage concordant, rien n'est écrasé sans une sauvegarde, et les
  applies restent atomiques.
- **Toujours une qualité de release.** Gardez les commentaires concis ; pas de commentaires gratuits.
- **Un changement logique par PR.** Dites ce qui a changé et pourquoi.

## Signaler des issues

Ouvrez une issue décrivant ce que vous avez fait, ce que vous attendiez et ce qui s'est passé.
Pour un bug, incluez l'id du module, le profil de la source (`hardened` ou `trusted`),
la commande `update.sh` que vous avez exécutée, et le `journal.json` pertinent (il enregistre la
phase, l'état et l'erreur). Pour une fonctionnalité, dites quel composant elle touche (moteur,
producteur, ou WebUI) afin que l'impact sur la couture soit clair d'emblée.
