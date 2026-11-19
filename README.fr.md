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

**VDLU** est un moteur d'automise à jour incrémentale et sans flash pour les modules **KernelSU / APatch / Magisk**. Un module installé se met à jour lui-même en ne récupérant **que les fichiers qui ont changé** (blobs adressés par contenu + un manifeste signé), applique à chaud ceux qu'il peut **sans redémarrage**, et prépare et signale les quelques-uns qui en exigent un (un `.so`, une surcouche `/system`, une `sepolicy.rule`). Pas de gestionnaire de root, pas de retéléchargement du `.zip` entier, pas de redémarrage sauf pour ces fichiers préparés.

Il est conçu pour être **intégré** (vendored) dans un module (déposé dans `<module>/vdlu/`), non pour être exécuté comme un module à part entière.

## Pourquoi

Une mise à jour de module classique renvoie le `.zip` entier. Pour un gros module, cela représente un retéléchargement massif pour quelques lignes modifiées, et un manifeste de mise à jour statique ne peut pointer que vers un seul `zipUrl`, de sorte qu'il ne peut pas servir la saveur (ABI, full vs lite) que l'appareil possède réellement. VDLU compare l'arbre **installé** à un feed signé et ne récupère que les deltas : ainsi une installation arm64-full reste arm64-full, une installation lite reste lite, et la plupart des mises à jour s'appliquent à chaud.

## Fonctionnement

- **Producteur (PC / release) :** `vdlu-pack` transforme un arbre de module en un feed adressé par contenu (`manifest.json` + `blobs/<sha256>`, gzip, déduplication, `delete[]`) ; `vdlu-keygen` / `vdlu-sign` (ed25519) ; `vdlu-gc` élague les blobs orphelins par référence aux N derniers manifestes (fail-safe, dry-run par défaut).
- **Moteur (appareil) :** POSIX sh, sans `jq`. `update.sh` (`check | run | resume | boot | status | cancel`) exécute DIFF -> FETCH -> APPLY -> COMMIT comme une **transaction reprenable** (journal), avec rollback et un verrou par `mkdir`. La signature est vérifiée par le `ed25519-mini` embarqué (pas d'`openssl` sur l'appareil).
- **WebUI :** un panneau Updates prêt à intégrer (toast de progression, annulation, bandeau de redémarrage), JS pur.

## Profils

- `trusted` : usage privé, source `file://` ou SSH, vérification best-effort (le hash toujours).
- `hardened` : usage public, **signature obligatoire**, downgrade bloqué. Le manifeste est **lié à l'id du module**, et chaque champ est validé fail-closed avant tout téléchargement.

## Adoptez-le dans votre module

Intégrez `engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` dans `<module>/vdlu/`, embarquez votre **clé publique brute de 32 octets** en tant que `vdlu/keyring/<id>.pub`, ajoutez un `config` (profil + source), câblez les déclencheurs (`post-fs-data.sh` pre-zygote pour l'automise à jour au démarrage ; un déclencheur à l'ouverture de la WebUI), et ajoutez `vdlu-pack` + `vdlu-sign` à votre release. Voir [`integration/`](integration/) pour un modèle complet.

## Sécurité

- **Chaque champ du manifeste est une entrée hostile.** `validate_plan()` rejette le manifeste entier fail-closed en cas de chemin absolu ou contenant `..`, de `sha256` qui n'a pas 64 caractères hexadécimaux, ou de mode / class / encoding invalide, **avant** tout fetch ou toute application.
- La **clé privée de signature ne touche jamais le CI ni un appareil** ; seule la clé publique brute est embarquée, et la vérification utilise `ed25519-mini`, pas `openssl`.
- `hardened` est fail-closed par inversion : tout ce qui n'est pas le littéral `trusted` est traité comme `hardened`, de sorte qu'une valeur de profil corrompue ne peut jamais accepter silencieusement un manifeste non signé.
- Les fichiers de classe redémarrage (`.so`, surcouche `/system`, `sepolicy.rule`) sont **préparés, jamais écrits par-dessus un inode en vie** ; tout le reste s'applique à chaud. Une application échouée abandonne plutôt que d'écraser sans sauvegarde.

## Compiler / tester

Ce sont des scripts, rien à compiler. De bout en bout (producteur + moteur ensemble) :

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

`sh -n engine/*.sh`, `node --check webui/vdlu.js`, et ouvrez `webui/demo.html` dans un navigateur (il simule le pont de l'appareil).

## Documentation

- [`INTERFACES.md`](docs/INTERFACES.md) : le contrat de couture entre les composants (la loi de convergence ; à considérer comme immuable).
- `integration/` : un guide d'adoption pas à pas et des extraits de câblage.

## Voir aussi

Projets frères du même auteur :

- **[VDBackup](https://github.com/VD171/VD-Backup)** : sauvegarde et restauration complètes des apps et des données en root, pilotées entièrement depuis une WebUI.
- **[COPG-VD](https://github.com/VD171/COPG-VD)** : un spoofer d'appareil qui transforme une empreinte fraîche en un profil cohérent et consistant.
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)** : un démon SSH en root, autonome et configurable, pour KernelSU/APatch/Magisk.
- **[VDInfos](https://github.com/VD171/VD-Infos)** : un débogueur de méthodes de l'appareil qui lit chaque élément à travers toutes les méthodes capables de le lire.
- **[VDGoogle](https://github.com/VD171/VD-Google)** : lit ce que Google enregistre sur votre appareil, entièrement en local et sans internet.

## Contacts

- https://vd171.ru
- https://vd.priv8.ru
- **Telegram:** @VD_Priv8 https://t.me/VD_Priv8
- **Channel:** @Priv8_VD https://t.me/Priv8_VD
- **Discord:** @VD.Priv8 https://discord.com/users/1296831918989639721
- **E-mail:** vd.priv8@pm.me
- **XDA-Developers:** @VD171 https://xdaforums.com/m/vd171.4699873/
- **GitHub:** @VD171 https://github.com/VD171

## Licence

Le code propre à VDLiveUpdate est sous **Apache-2.0** ; voir [LICENSE](LICENSE). Il intègre un petit vérificateur
`ed25519-mini` et un `curl` statique pour l'amorçage du téléchargement, chacun sous sa propre licence ; voir
[NOTICE.md](NOTICE.md) et les fichiers `PROVENANCE.json` à côté des binaires fournis.

## Marques

VDLiveUpdate est un projet indépendant et non officiel, non affilié ni approuvé par un quelconque tiers.
« Android » est une marque de Google LLC ; « KernelSU », « Magisk » et « APatch » sont les marques de leurs
auteurs respectifs. VDLU s'exécute entièrement sur votre appareil et sur votre propre hôte de release.

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`

---

📣 **Join the channel for updates:** @Priv8_VD https://t.me/Priv8_VD
