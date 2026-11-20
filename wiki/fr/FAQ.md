# FAQ

Réponses courtes aux questions qui reviennent le plus. Chacune renvoie à la page avec
l'histoire complète.

## Que signifie "sans flashage" (flashless) ? Dois-je quand même flasher la première fois ?

Oui, vous flashez une fois. Le module est installé de la manière normale (flasher le zip dans
votre gestionnaire root). "Sans flashage" décrit chaque mise à jour après cela : VDLU récupère
uniquement les fichiers qui ont changé et les applique sur place, de sorte que vous ne reflashez jamais un
zip complet juste pour livrer quelques lignes modifiées. Voir [[Architecture]].

## Une mise à jour nécessite-t-elle un redémarrage ?

Habituellement non. La plupart des fichiers (votre WebUI, binaires, bibliothèques, configs, `module.prop`)
sont de classe **live** et s'appliquent de manière atomique sans redémarrage. Seuls les fichiers de classe reboot
(un `.so` sous `zygisk/`, un overlay `/system/**`, un fichier sepolicy `*.rule`) sont
**échelonnés** et échangés au prochain démarrage, parce qu'un processus en cours d'exécution a déjà
mappé l'inode en direct. Lorsque cela arrive la WebUI affiche une bannière persistante "reboot to
activate". Voir [[Reboot Handling]].

## Est-ce sûr si le feed subit un MITM ou est empoisonné ?

Oui, sur un feed `hardened`. Chaque champ du manifeste est traité comme une entrée hostile.
Le manifeste doit porter une signature ed25519 valide sur sa forme canonique, et
`validate_plan()` s'exécute en fail-closed **avant tout téléchargement** : il rejette le manifeste
entier au moindre chemin absolu ou `..`, un `sha256` qui ne fait pas 64 caractères hex,
ou un mode, class ou encoding invalide. Le manifeste est aussi lié à l'id de votre module,
de sorte qu'un feed valablement signé pour un module différent ne puisse être servi à sa place.
Le sha256 de chaque blob est vérifié après le téléchargement quel que soit le profil. Voir
[[Security and Trust Model]].

## De quoi a-t-il besoin sur l'appareil (dépendances) ?

Très peu. `sh` POSIX pur (mksh / busybox / toybox) plus le `sha256sum`,
`gzip`, `base64` et `date` de toybox ; le vérificateur `ed25519-mini` embarqué ; et, uniquement pour
une source `https`, un `curl` statique récupéré une fois et mis en cache en Tier-2.
Une source `file://` n'a besoin d'aucun curl. Il n'y a **aucune dépendance à `jq`** : le
moteur analyse le JSON avec un aplatisseur de style gron écrit en `awk`. Voir [[Engine]].

## openssl est-il requis sur l'appareil ?

Non. `openssl` n'est utilisé que du côté PC/publication (`vdlu-keygen`, `vdlu-sign`).
Sur l'appareil, la vérification de signature utilise le mince binaire embarqué `ed25519-mini`,
qui lit une clé publique de 32 octets BRUTS. Voir [[Producer]] et
[[Security and Trust Model]].

## Comment faire la rotation de la clé de signature ?

Générez une nouvelle paire de clés avec `vdlu-keygen`, ajoutez la nouvelle clé publique de 32 octets bruts au
keyring de l'appareil à côté de la précédente, et commencez à signer avec le nouveau
`key_id`. L'appareil choisit `<keyring>/<key_id>.pub` par le `key_id` du manifeste,
de sorte qu'aucun changement de moteur n'est nécessaire. Livrer à la fois la clé publique courante et la précédente
signifie qu'une clé tournée ne brique jamais les anciennes installations. Parce qu'une rotation laisse plus d'une clé dans le keyring, vous devez aussi épingler quelle clé peut signer une mise à jour de module : définissez la config `key_id` (séparées par des virgules pendant la fenêtre de rotation). Un keyring à clé unique s'épingle automatiquement et n'a besoin d'aucune config. Voir [[Security and Trust Model]].

## hardened vs trusted - lequel utiliser ?

Utilisez `hardened` pour tout feed public (servi via `https`, par ex. GitHub Pages).
Il rend la signature obligatoire et bloque les downgrades. Utilisez `trusted` uniquement pour une
source privée `file://` ou par SSH que vous contrôlez déjà, où la signature
est au mieux (chaque hachage de blob est quand même vérifié). Dans le doute, utilisez `hardened` :
c'est le défaut fail-closed, et toute valeur non-`trusted` est traitée comme
`hardened`. Voir [[Security and Trust Model]].

## Que se passe-t-il si un blob est altéré ou le manifeste malformé ?

La mise à jour est interrompue et rien n'est appliqué. Un manifeste malformé est rejeté entier
par `validate_plan()` avant tout fetch. Un blob dont le sha256 ne correspond pas au
manifeste est rejeté ; trois échecs sur le même blob interrompent la phase de fetch sans
rien appliquer. À tout échec dur le journal enregistre `ERROR` et le module
est laissé intact. Voir [[Engine]].

## Une mise à jour peut-elle supprimer mes fichiers ou briquer l'appareil ?

Le risque est confiné par conception. Les fichiers écrasés et supprimés sont d'abord sauvegardés
vers `rollback/<version>/`, et `apply` est interrompu plutôt que d'écraser sans une
sauvegarde réussie. Les suppressions ne s'exécutent que lorsqu'une transaction atteint `DONE`, jamais
tant qu'un redémarrage est encore en attente. Un apply en échec revient en arrière sur les fichiers en direct qu'il a déjà
écrits. Les chemins sont validés pour leur confinement dans le répertoire du module avant usage,
de sorte qu'un manifeste ne peut ni écrire ni supprimer hors de l'arborescence. Voir [[Engine]] et
[[Security and Trust Model]].

## Fonctionne-t-il sur KernelSU ET Magisk ET APatch ?

Oui. VDLU est du `sh` POSIX simple plus une WebUI, intégré au module, de sorte qu'il tourne sur
KernelSU, APatch et Magisk de la même façon. Il utilise le pont WebUI du gestionnaire root
(`ksu.exec`) pour piloter le moteur et sonder la progression. Voir [[Architecture]] et
[[WebUI]].

## Quelle est la taille de l'empreinte sur l'appareil ?

Petite. Le moteur, ce sont des scripts ; les seuls binaires sont le vérificateur `ed25519-mini` par ABI
(minuscule) et, pour une source `https`, un `curl` statique (~1MB) qui est
récupéré une fois et mis en cache. Un module qui empaquette déjà son propre `curl` le réutilise
et n'ajoute aucun téléchargement. Le cache de blobs Tier-2 contient le contenu vérifié plus
les 3 dernières versions de rollback. Voir [[Engine]] et [[Architecture]].
