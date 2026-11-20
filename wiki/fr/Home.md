# VDLiveUpdate (VDLU)

**VDLU est un moteur de mise à jour automatique, incrémentale et sans flashage pour les modules KernelSU / APatch / Magisk : un module installé met à jour ses propres fichiers via un feed signé, en récupérant uniquement ce qui a changé et en appliquant l'essentiel sans redémarrage.**

Une mise à jour de module classique renvoie l'intégralité du `.zip`, de sorte que quelques lignes modifiées coûtent un retéléchargement complet, et un manifeste de mise à jour statique ne peut pointer que vers un unique `zipUrl` (une seule variante pour tous les appareils). VDLU emprunte une autre voie : il compare l'arborescence réellement installée à un feed signé et adressé par contenu, télécharge uniquement les deltas et les écrit sur place. Une installation arm64 complète reste arm64 complète, une installation lite reste lite, et le module n'est jamais reflashé.

VDLU est conçu pour être **intégré (vendored)** dans un module, déposé dans `<module>/vdlu/`. Ce n'est pas un module à part entière.

## Objectifs

- **Mise à jour automatique sans flashage.** Mettre à jour un module installé sur place, par voie réseau, sans gestionnaire root, sans reflasher le `.zip` et sans perdre la variante installée.
- **Incrémental par contenu.** Ne transférer que les blobs dont le contenu a changé. Un feed adressé par contenu (`manifest.json` + `blobs/<sha256>`) garantit que les fichiers inchangés ou revenus en arrière ne sont jamais retéléchargés.
- **Sans redémarrage lorsque c'est sûr.** Appliquer les fichiers ordinaires en direct, immédiatement. Réserver un redémarrage échelonné uniquement aux rares fichiers qui l'exigent vraiment (un `.so`, un overlay `/system`, un `sepolicy.rule`).
- **Léger sur l'appareil.** `sh` POSIX pur, sans `jq`, sans `bash`, sans `openssl` sur l'appareil. La vérification repose sur un `ed25519-mini` embarqué ; le seul binaire téléchargé est un `curl` statique, utilisé uniquement pour les feeds `https`.
- **Fail-closed et honnête.** Chaque champ du manifeste est traité comme une entrée hostile et validée avant tout téléchargement. Rien n'est jamais rapporté comme "terminé" à moins qu'un re-hachage ne le prouve, et rien n'est écrasé sans une sauvegarde préalable.

## Particularités

Ce qui distingue VDLU d'un client OTA classique :

- **Sans flashage et incrémental.** Diff / fetch / apply adressé par contenu avec déduplication : l'appareil calcule le delta par rapport au feed signé et ne récupère que les blobs manquants.
- **Sans redémarrage lorsque c'est possible.** Les fichiers ordinaires s'appliquent en direct ; seuls les `.so`, les overlays `/system` et les fichiers `sepolicy.rule` sont échelonnés et échangés lors d'un unique redémarrage. Voir [[Reboot Handling]].
- **`sh` POSIX sur l'appareil.** Fonctionne sous toybox / busybox / mksh. Sans `jq` (un aplatisseur `awk` de style `gron` analyse le JSON), sans `bash`ismes, sans runtime lourd.
- **Vérification légère.** Un `ed25519-mini` embarqué vérifie les signatures. Il n'y a **pas d'`openssl` sur l'appareil** ; la clé privée ne touche jamais un appareil ni la CI.
- **Sécurité fail-closed.** `validate_plan()` rejette le manifeste **entier** au moindre champ invalide (un chemin absolu ou avec `..`, un `sha256` qui ne fait pas 64 caractères hex, un mode / class / encoding invalide). Deux profils, `trusted` et `hardened`, `hardened` étant fail-closed par inversion. Voir [[Security and Trust Model]].
- **Reprenable et atomique.** Un journal rend chaque transaction résistante aux pannes ; les écritures utilisent `rename` / `mv` ; une sauvegarde est prise avant tout écrasement, de sorte qu'un apply en échec revient en arrière au lieu de corrompre le module.

## Commencer ici

| Si vous voulez... | Allez à |
|---|---|
| Adopter VDLU dans votre module, étape par étape | [[Quick Start]] |
| Comprendre l'ensemble du système d'un coup d'oeil | [[Architecture]] |
| Apprendre le moteur côté appareil (`update.sh`) | [[Engine]] |
| Construire et signer un feed sur votre PC | [[Producer]] |
| Insérer le panneau Updates | [[WebUI]] |
| Lire le modèle de confiance et la posture face aux menaces | [[Security and Trust Model]] |
| Voir la disposition du manifeste et des blobs | [[Feed Format]] |
| Savoir ce qui redémarre et pourquoi | [[Reboot Handling]] |
| Poser une question fréquente | [[FAQ]] |
| Contribuer | [[Contributing]] |

## Liens du projet

- **Code source :** https://github.com/VD171/VDLiveUpdate
- **Canal (mises à jour) :** @Priv8_VD https://t.me/Priv8_VD

VDLiveUpdate est un projet indépendant et non officiel. "Android" est une marque de Google LLC ; "KernelSU", "Magisk" et "APatch" sont les marques de leurs auteurs respectifs. VDLU s'exécute entièrement sur votre appareil et votre propre hôte de publication.
