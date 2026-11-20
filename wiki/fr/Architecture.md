# Architecture

VDLU comporte deux côtés reliés par une seule chose au milieu. Sur le PC, le [[Producer]] transforme l'arborescence d'un module en un feed signé et adressé par contenu. Sur l'appareil, le [[Engine]] lit ce feed, détermine ce qui a changé et l'applique. La couture entre les deux est le **manifeste signé plus le magasin de blobs** (le [[Feed Format]]). Rien d'autre ne traverse l'écart.

```
        PC / release host                                device
  +--------------------------+                 +---------------------------+
  |  Producer                |                 |  Engine  (update.sh)      |
  |  vdlu-pack  -> manifest  |    signed       |  POSIX sh, no jq          |
  |  vdlu-sign  -> sig       |    feed         |  DIFF FETCH APPLY COMMIT  |
  |  vdlu-gc    -> prune     | =============>  |  journal + rollback       |
  +--------------------------+   manifest.json |  ed25519-mini verify      |
                                 blobs/<sha>   +-------------+-------------+
                                                             |
                                                       +-----v------+
                                                       |  WebUI     |
                                                       |  Updates   |
                                                       |  panel     |
                                                       +------------+
```

Les deux côtés ne partagent jamais de runtime. Le Producer utilise `python3` et `openssl` ; le Engine est du `sh` POSIX pur avec toybox et un `ed25519-mini` embarqué. Ils ne concordent que parce que les deux dérivent les **mêmes octets canoniques** d'un manifeste (voir [[Security and Trust Model]]). La WebUI est un panneau mince en JS vanilla qui pilote le moteur via le pont du gestionnaire root et lit son journal de progression ; elle ne contient aucune logique de mise à jour propre. Voir [[WebUI]].

## Les deux côtés

| Côté | Tourne sur | Construit avec | Rôle |
|---|---|---|---|
| [[Producer]] | PC / CI | `python3` + `sh` + `openssl` | Parcourir l'arborescence du module vers `manifest.json` + `blobs/`, la signer, élaguer les orphelins |
| [[Engine]] | appareil | `sh` POSIX + toybox + `ed25519-mini` | Comparer l'arborescence installée au feed, récupérer les deltas, appliquer, valider |
| [[WebUI]] | appareil (webview) | JS/CSS vanilla | Déclencher les mises à jour, afficher la progression, éditer la config, afficher la bannière de redémarrage |

## Le pipeline de mise à jour

Chaque mise à jour est une transaction, exécutée dans un ordre fixe :

```
  DIFF  ------>  FETCH  ------>  APPLY  ------>  COMMIT
  read feed      download        write live     re-hash all,
  + validate     only missing    files now,      promote target
  + plan         blobs, verify   stage reboot     -> current,
  (no changes)   each sha256     ones             DONE or
                                                  PENDING_REBOOT
```

- **DIFF** (`update.sh check` correspond à cette phase, en lecture seule). Le moteur ne télécharge que le manifeste, exécute `validate_plan()` sur chaque champ **avant** de toucher à quoi que ce soit, puis compare le feed à `current.json` pour construire un plan fichier par fichier. Il ne change rien sur le disque. Un appareil en avance sur le feed est un résultat bénin "ahead", pas une erreur.
- **FETCH.** Télécharge uniquement les blobs manquants au plan, vers `<sha>.part`, décompresse `gz`, vérifie `sha256sum` par rapport au manifeste, et déplace de manière atomique (`mv`) chaque blob vérifié dans le cache. Un blob déjà en cache (ou amorcé depuis un fichier local inchangé) est sauté, de sorte qu'un retour en arrière ou un fichier partagé ne coûte rien. Trois échecs sur un même blob interrompent la phase sans rien appliquer. Un téléchargement bloqué par la politique réseau se termine en `DEFERRED` (reprenable), pas en erreur.
- **APPLY.** Les fichiers ordinaires (`live` / `soft`) sont écrits maintenant : sauvegarde vers `rollback/<v>/`, écriture d'un `.vdlu-tmp`, `chmod`, vérification, puis `rename` atomique par-dessus la cible. Les fichiers de classe reboot sont matérialisés dans `staged/<path>.vdlu-new` et l'inode en direct est laissé intact. Une entrée `delete[]` est sauvegardée, puis supprimée. Chaque étape est idempotente : un fichier déjà au hachage cible est sauté.
- **COMMIT.** Re-hacher chaque fichier en direct ; ce n'est que si tout correspond que le moteur promeut `target.json` en `current.json`. Si quelque chose a été échelonné, la transaction se termine en `PENDING_REBOOT` ; sinon `DONE`.

## Manifeste et blobs adressés par contenu

Le feed est adressé par contenu : le manifeste liste l'arborescence cible **complète**, chaque fichier porté par son `sha256`, et le magasin de blobs conserve une copie de chaque contenu distinct sous `blobs/<sha256>` (ou `blobs/<sha256>.gz`).

- **Déduplication.** Un contenu identique n'importe où dans l'arborescence, ou entre releases, est un seul blob. La publication est incrémentale : un blob dont le `sha256` existe déjà sur l'hôte n'est jamais repoussé, et l'appareil ne retélécharge jamais un contenu qu'il possède déjà.
- **Le sha256 est celui de l'original.** Le hachage nomme toujours le contenu non compressé ; `enc` (`raw` ou `gz`) n'enregistre que la manière dont ce blob se trouve stocké. L'appareil décompresse `gz` avec le `gunzip` de toybox, de sorte qu'aucun compresseur supplémentaire n'est embarqué.
- **Stable par variante.** Parce que l'appareil compare à ce qui est réellement installé, le feed peut porter toute une famille de modules ; chaque installation ne récupère que les blobs qui complètent sa propre variante.

La disposition champ par champ complète figure dans [[Feed Format]].

## Le journal reprenable

Chaque transaction résiste aux pannes parce que sa progression vit dans un journal (`journal.json`), et la cible épinglée de la transaction en cours vit dans `target.json`. La machine à états s'exécute dans un ordre fixe :

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> ( PENDING_REBOOT | DONE )
                                                               \-> ERROR / DEFERRED
```

| État | Signification |
|---|---|
| `PLANNED` | Plan construit, rien de récupéré encore |
| `FETCHING` / `FETCHED` | Téléchargement des blobs / tous les blobs présents et vérifiés |
| `APPLYING` / `APPLIED_LIVE` | Écriture des fichiers / tous les fichiers en direct écrits |
| `PENDING_REBOOT` | Un fichier de classe reboot est échelonné, en attente de l'échange au démarrage |
| `DONE` | Le re-hachage de tout a correspondu ; `current.json` promu |
| `ERROR` | Échec dur ; le module reste non corrompu, les fichiers en direct revenus depuis `rollback/` |
| `DEFERRED` | Téléchargement retenu par la politique réseau ; le plan persiste, reprend plus tard |

`DONE` n'est atteint **que** lorsqu'un re-hachage de tout correspond, de sorte que le journal ne prétend jamais qu'une mise à jour appliquée à moitié est complète. Une panne, une coupure réseau ou un redémarrage à mi-chemin laisse un journal reprenable ; `update.sh resume` (ou `boot`) reprend à partir de la phase courante. Voir [[Engine]] pour le jeu de commandes et les fichiers d'état sur l'appareil.

## Atomicité et rollback

Rien n'est jamais écrasé sur place et rien n'est perdu :

- **Écritures atomiques.** Chaque fichier atterrit via un temporaire (`.vdlu-tmp`) et un `rename` / `mv` atomique, de sorte qu'un lecteur ne voit jamais un fichier à moitié écrit.
- **Sauvegarde avant écrasement.** Le contenu précédent va vers `rollback/<version>/<path>` avant que le nouveau fichier ne soit renommé par-dessus (les dernières versions sont conservées). Si un apply échoue, les fichiers en direct sont revenus depuis la copie de rollback plutôt que laissés corrompus. Une sauvegarde en échec **interrompt** l'apply au lieu d'écraser sans filet de sécurité.
- **Sérialisé.** Un verrou basé sur `mkdir` (`lock.d/`, car `flock` est inutilisable sur toybox, avec récupération des verrous périmés par PID) sérialise les exécutions concurrentes.

## Le principe sans redémarrage

La plupart des fichiers peuvent être échangés pendant que le module est en direct, aussi VDLU les applique immédiatement. Seules trois classes nécessitent un redémarrage, parce qu'un processus en direct les a déjà mappés : un `.so` (chargé par Zygisk), un overlay `/system` et un `sepolicy.rule`. Ceux-là sont **échelonnés, jamais écrits par-dessus un inode en direct**, et échangés en une seule étape pré-zygote au prochain démarrage. La taxonomie complète et le flux de démarrage figurent dans [[Reboot Handling]].

## La posture de confiance fail-closed

Le feed est la seule chose qui traverse du PC vers l'appareil, aussi le moteur traite chacun de ses octets comme hostile. `validate_plan()` s'exécute dans la phase DIFF, avant tout téléchargement, et rejette le manifeste entier au moindre champ malformé. La vérification de signature utilise un `ed25519-mini` embarqué (pas d'`openssl` sur l'appareil), la clé privée ne touche jamais un appareil ni la CI, et le profil `hardened` est fail-closed par inversion, de sorte qu'une valeur de profil corrompue ne peut jamais accepter silencieusement un feed non signé. Le modèle complet, les deux profils et les menaces auxquelles chacun répond figurent dans [[Security and Trust Model]].
