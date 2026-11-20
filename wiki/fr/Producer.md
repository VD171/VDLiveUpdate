# Producer

Le **producteur** est le côté PC / publication de VDLU : le petit ensemble d'outils qui transforment une arborescence de module finalisée en un feed signé et adressé par contenu depuis lequel l'appareil peut se mettre à jour. Rien ici ne tourne sur le téléphone. Ces outils tournent sur votre machine de publication (ou, pour les parties où c'est sûr, en CI).

Il y en a quatre :

| Outil | Tourne sur | Langage | Rôle |
|---|---|---|---|
| `vdlu-pack` | PC / CI | python3 | Parcourir l'arborescence finale du module vers `manifest.json` + `blobs/<sha256>` |
| `vdlu-keygen` | PC | sh + openssl | Générer une paire de clés de signature ed25519 |
| `vdlu-sign` | PC | sh + openssl | Injecter `key_id` + signature dans un manifeste, sur place |
| `vdlu-gc` | PC | python3 | Élaguer les blobs orphelins d'un feed publié (fail-safe) |

Le flux de publication tient en trois étapes, effectuées une fois par release : **packer, puis signer, puis publier**. `vdlu-keygen` est une mise en place ponctuelle, et `vdlu-gc` est un entretien que vous lancez lorsque le feed grossit. Tout ce que le producteur émet se conforme au [[Feed Format]], qui est ce que le moteur sur l'appareil consomme.

---

## vdlu-pack

`vdlu-pack` prend l'**arborescence exacte que votre `.zip` livre** (l'arborescence finale, après que votre build a appliqué sa propre liste blanche et son élagage d'ABI) et produit le feed correspondant.

```sh
vdlu-pack <module_tree_dir> <out_dir> <module_id> <version> \
          [--version-name v106] [--channel stable] [--prev ./prev/manifest.json]
```

Il écrit deux choses dans `<out_dir>` :

- `manifest.json` - la description complète de l'arborescence cible (chaque fichier avec son `sha256`, `size`, `mode`, encodage et classe de redémarrage), encore **non signée** (les champs `key_id` et `sig` sont des espaces réservés vides).
- `blobs/<sha256>` (ou `blobs/<sha256>.gz`) - un blob par contenu de fichier distinct.

### Adressé par contenu et déduplication

Chaque blob est nommé par le **sha256 de son contenu original (non compressé)**. Parce que le nom est le hachage, un contenu identique atterrit sur le même blob. `vdlu-pack` n'écrit un blob que s'il n'est pas déjà présent, ainsi :

- Un fichier qui n'a pas changé garde le même nom de blob, et n'est jamais réécrit ni repoussé.
- Deux fichiers différents au contenu identique partagent un seul blob.
- Un fichier revenu en arrière réutilise le blob qui était déjà là auparavant.

La publication est donc **incrémentale par construction** : d'une release à l'autre, `blobs/` ne fait que grandir, et seul un contenu réellement nouveau est ajouté. L'appareil télécharge par les mêmes hachages, aussi il ne récupère que les blobs qu'il ne détient pas déjà.

### Compression (le champ `enc`)

Pour chaque fichier, `vdlu-pack` décide comment stocker le blob :

- `gz` quand le fichier fait au moins 4096 octets **et** que gzip (déterministe `-9 -n`) économise au moins 10 pour cent.
- `raw` sinon (petits fichiers que le gzip sur le fil couvre déjà, ou données déjà incompressibles).
- Si `gzip` est absent sur l'hôte de build, tout est stocké en `raw`. Le packaging n'échoue jamais pour cette raison.

Le `sha256` dans le manifeste est **toujours** celui du contenu original ; `enc` ne nomme que la manière dont le blob se trouve stocké. L'appareil décompresse les blobs `gz` avec le `gunzip` de toybox puis vérifie le hachage par rapport à l'original.

### Classe de redémarrage et sécurité

`vdlu-pack` étiquette aussi chaque fichier avec une `class` de redémarrage (`live`, `soft`, `reboot`) dérivée de son chemin, afin que le moteur sache ce qui peut être appliqué sans redémarrage et ce qui doit être échelonné. Les règles et ce que l'appareil fait de chaque classe sont couverts dans [[Reboot Handling]].

Quelques choses que `vdlu-pack` ne fait délibérément **pas** :

- Il ne suit pas les liens symboliques (il les saute avec un avertissement, de sorte qu'un contenu hors de l'arborescence, comme un lien vers un fichier système, ne puisse jamais fuiter dans un blob).
- Il saute les fichiers non réguliers (répertoires, fifos, périphériques).
- Il respecte `SOURCE_DATE_EPOCH` pour l'horodatage `built`, afin que les manifestes soient reproductibles.
- Il exclut entièrement du feed un ensemble fixe de chemins (la racine de confiance, l'échafaudage d'installeur, et quelques autres). La liste complète, et pourquoi chacun est exclu, figure dans [[Feed Format]].

### La liste `delete[]`

Passez `--prev <manifest.json précédent>` et `vdlu-pack` calcule `delete[]` : les chemins qui existaient dans la release précédente mais ont disparu dans celle-ci, afin que l'appareil les supprime au lieu de laisser des orphelins derrière. Les chemins exclus ne sont jamais émis comme suppressions, même lorsqu'ils apparaissent dans le manifeste précédent (voir [[Feed Format]] pour la sémantique exacte).

---

## vdlu-keygen

Une étape ponctuelle. `vdlu-keygen` crée la paire de clés de signature ed25519 pour votre feed.

```sh
vdlu-keygen <id> <out_dir>
```

Il écrit trois fichiers :

| Fichier | Ce que c'est | Où il va |
|---|---|---|
| `<id>.pem` | La clé de signature **privée** (mode `0600`) | Reste sur votre machine de publication. Jamais. |
| `<id>.pub` | La clé publique au format PEM | Outillage côté PC uniquement |
| `<id>.pub.raw` | La clé publique en **32 octets bruts** | Livrée comme l'entrée du keyring sur l'appareil du module |

La clé publique de 32 octets bruts est ce que le vérificateur de l'appareil lit (il n'embarque pas d'`openssl`, donc il ne peut pas lire le PEM). Vous embarquez `<id>.pub.raw` dans le module sous `vdlu/keyring/<id>.pub`. Le PEM est pour un usage côté PC uniquement. Cette séparation, et le fonctionnement de la rotation de clé, sont expliqués dans [[Security and Trust Model]].

> **Un keyring à plusieurs clés doit épingler `key_id`.** Si le keyring du module livre plus d'une clé (par exemple la clé de release plus une clé de feed de fingerprint de moindre confiance), le moteur ne devinera pas laquelle peut signer une mise à jour de module. Définissez la config `key_id` sur la clé, ou les clés séparées par des virgules pendant une fenêtre de rotation, qui est autorisée à signer les mises à jour ; un keyring à clé unique s'épingle automatiquement et n'a besoin d'aucune config. C'est la liste d'autorisation de mise à jour de module, couverte dans [[Security and Trust Model]].

> Le `.pem` privé est le seul secret de tout le système. Gardez-le hors de tout appareil et hors de tout push de dépôt. Voir la note CI ci-dessous.

---

## vdlu-sign

`vdlu-sign` prend le manifeste non signé produit par `vdlu-pack` et le signe **sur place**.

```sh
vdlu-sign <manifest.json> <privkey.pem> <key_id>
```

Il définit le champ `key_id`, calcule la forme canonique du manifeste, et écrit la signature ed25519 (base64) dans le champ `sig`. La signature porte sur une transformation d'octets précise du manifeste, de sorte que le PC et l'appareil dérivent exactement les mêmes octets signés sans aucune bibliothèque JSON sur l'appareil. Cette transformation (la **canonicalisation**) est l'invariant le plus important du format, et elle est documentée en détail dans [[Feed Format]].

La clé privée n'est lue qu'ici, sur votre machine, et ne la quitte jamais.

### La clé de signature reste hors de la CI

C'est un point de conception délibéré. La CI peut exécuter `vdlu-pack` et produire une **baseline sans clé** parfaitement valide (un manifeste de semence non signé ; voir [[Feed Format]]), de sorte qu'une nouvelle installation naît à jour sans que la CI ne touche jamais une clé privée. La signature réelle du feed publié est effectuée par vous, localement, avec `vdlu-sign`. Ainsi la clé de signature est à 100 pour cent hors de la CI, et seul le feed que vous publiez à la main est signé.

---

## vdlu-gc

Parce que les blobs sont adressés par contenu et immuables, `blobs/` ne fait que grandir : `vdlu-pack` ajoute, il ne retire jamais. Au fil de nombreuses releases le feed (et le site Pages qui l'héberge) accumule des blobs qu'aucun manifeste courant ne référence plus. `vdlu-gc` élague ces orphelins.

```sh
vdlu-gc <feed_dir> [--keep-last N] [--keep extra.json ...] [--apply]
```

Il construit l'**ensemble retenu** de manifestes : le `manifest.json` courant, plus les `N` derniers manifestes archivés par version (par défaut `N=3`, donnant une marge de rollback), plus tous ceux que vous nommez avec `--keep`. Un blob référencé par **aucun** manifeste retenu est un orphelin et un candidat à la suppression. L'ensemble retenu est une union, aussi un blob reste tant qu'une release retenue en a encore besoin ; un appareil resté sur une version retenue plus ancienne ne perd jamais son fetch.

`vdlu-gc` est conçu pour être sûr :

- **Dry-run par défaut.** Sans `--apply`, il n'imprime que ce qu'il *supprimerait*. Vous ajoutez `--apply` pour supprimer réellement.
- **Fail-safe.** S'il ne trouve aucun manifeste retenu, il refuse d'élaguer plutôt que de risquer de vider un feed.
- **Rétention par référence, pas par date.** Un blob est conservé parce qu'un manifeste retenu pointe vers lui, jamais à cause d'un horodatage.

Après l'élagage, poussez le feed réduit vers votre hôte. Étalez l'écriture si votre hôte limite le débit des écritures par lots.

---

## Mise en oeuvre

Une release typique, de bout en bout :

```sh
# one-time: make a signing key. Keep the .pem off every device and every repo push.
vdlu-keygen release-2026 ./keys

# each release: pack the final shipped tree (post-whitelist, same tree the .zip ships)
vdlu-pack ./module_tree ./out demo 106 --version-name v106 --channel stable \
          --prev ./prev/manifest.json

# sign the manifest in place (local, private key never leaves your machine)
vdlu-sign ./out/manifest.json ./keys/release-2026.pem release-2026

# publish ./out/{manifest.json,blobs/} to your source (GitHub Pages, rsync, ...).
# occasionally: prune orphan blobs
vdlu-gc ./feed --keep-last 3            # dry-run first
vdlu-gc ./feed --keep-last 3 --apply    # then delete
```

Pour l'exemple complet et détaillé d'adoption de VDLU dans un module, voir [[Quick Start]]. Pour la forme sur le fil de tout ce que le producteur émet, voir [[Feed Format]]. Pour le raisonnement derrière la gestion des clés et ce qui est tenu hors du feed, voir [[Security and Trust Model]].
