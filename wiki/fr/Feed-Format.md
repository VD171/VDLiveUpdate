# Feed Format

Le **feed** est ce que VDLU sert sur le fil et ce depuis quoi l'appareil se met à jour. C'est un simple répertoire statique, servable par n'importe quoi (GitHub Pages, une cible rsync, un chemin `file://`) :

```
<source>/
  manifest.json          # the signed description of the current release
  blobs/<sha256>         # one blob per distinct file content
  blobs/<sha256>.gz      # (when the blob is stored gzipped)
```

Le module lui-même livre aussi un fichier supplémentaire, `baseline.json`, à l'intérieur du `.zip` (non servi depuis le feed). Le producteur qui construit tout ceci est décrit dans [[Producer]] ; cette page est le contrat sur le fil.

---

## manifest.json

Le manifeste est la description complète d'une release : chaque fichier de l'arborescence cible, ce qu'il faut supprimer, et la signature sur l'ensemble.

```json
{
  "schema": 1,
  "module": "demo",
  "version": 106,
  "version_name": "v106",
  "built": "2026-11-19T12:00:00Z",
  "engine_min": 3,
  "channel": "stable",
  "key_id": "release-2026",
  "files": [
    {
      "path": "webroot/index.html",
      "sha256": "<hex64>",
      "size": 1234,
      "mode": "0644",
      "enc": "raw",
      "class": "live"
    }
  ],
  "delete": ["webroot/old.html"],
  "sig": "<base64>"
}
```

### Champs

| Champ | Signification |
|---|---|
| `schema` | Version de format du manifeste lui-même (actuellement `1`). |
| `module` | L'id du module. L'appareil rejette le manifeste s'il ne correspond pas à son propre id de module, de sorte qu'un feed valablement signé pour un module différent ne puisse être servi à sa place. |
| `version` | Version entière. Le moteur met à jour uniquement vers l'avant ; un feed plus ancien que l'appareil est un état bénin "ahead", pas une erreur. |
| `version_name` | Chaîne de version lisible par l'humain (par exemple `v106`). |
| `built` | Horodatage de build ISO 8601. Respecte `SOURCE_DATE_EPOCH` pour la reproductibilité. |
| `engine_min` | La version minimale du moteur requise pour appliquer ce manifeste. |
| `channel` | Canal de release (par exemple `stable`). |
| `key_id` | Quelle clé du keyring de l'appareil a signé ce manifeste. Sélectionne la clé publique pour la vérification, et doit figurer dans la liste d'autorisation de mise à jour de module du moteur (voir [[Security and Trust Model]]) ; une clé simplement présente dans le keyring mais non autorisée est rejetée avant que sa clé publique ne soit chargée. |
| `files[]` | L'arborescence cible **complète** (pas un diff). Chaque entrée : `path`, `sha256`, `size`, `mode`, `enc` (`raw`/`gz`), `class` (`live`/`soft`/`reboot`). |
| `delete[]` | Chemins présents dans la release précédente mais disparus maintenant, pour que l'appareil les supprime. |
| `sig` | La signature ed25519, base64. Voir la canonicalisation ci-dessous. |

`files[]` décrit l'arborescence **entière**, pas un delta. L'appareil calcule le delta lui-même en comparant le manifeste à ce qu'il possède déjà, et ne récupère que les blobs dont le `sha256` lui manque. Le `sha256` est toujours celui du contenu original (non compressé) ; `enc` dit seulement comment ce blob est stocké dans `blobs/`. La signification de `class` et ce que l'appareil fait de chaque valeur est couvert dans [[Reboot Handling]].

---

## Canonicalisation (les octets signés)

C'est l'invariant le plus important du format. Le signataire du PC et le vérificateur de l'appareil tournent sur des runtimes complètement différents (openssl sur le PC, toybox + un minuscule vérificateur embarqué sur l'appareil, et **aucune bibliothèque JSON du tout** sur l'appareil). Ils doivent néanmoins dériver exactement les mêmes octets pour signer et pour vérifier. La règle est donc une **transformation d'octets** délibérée, pas une re-sérialisation JSON.

**Étape 1 : une forme de stockage fixe.** `vdlu-pack` écrit `manifest.json` compact, clés triées, UTF-8, incluant toujours `key_id` et `sig` (comme chaînes vides jusqu'à la signature) :

```
json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
```

**Étape 2 : retirer uniquement `sig`.** La forme canonique est ce texte exact avec **uniquement le champ `"sig"` retiré**. Parce que les clés sont triées, `sig` apparaît toujours comme `,"sig":"<value>",` encadré par `"schema"` avant et `"version"` après (tous deux toujours présents), de sorte que le retirer laisse un texte bien formé. JSON échappe chaque `"` à l'intérieur d'une valeur de chaîne comme `\"`, de sorte que le token structurel `"sig":"` est non ambigu même face à un nom de fichier qui contient littéralement `"sig":"`.

Le retrait est une poignée d'expansions de paramètres POSIX, identiques dans le signataire et le vérificateur, sans `sed` et sans `jq` :

```sh
# $1 = the full manifest text
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

**Étape 3 : signer le hachage de cela.** Le message signé/vérifié est le **sha256 hex** (64 caractères ASCII, sans newline) de la forme canonique. ed25519 signe ce hex.

Deux conséquences découlent de cela par construction :

- `key_id` fait partie de la forme canonique (seul `sig` est retiré). `vdlu-sign` définit `key_id` **avant** de hacher, de sorte que l'identité de la clé est couverte par la signature.
- Que l'espace réservé `sig` soit vide (`"sig":""`, au moment de signer) ou rempli (au moment de vérifier), le retirer donne les mêmes octets canoniques identiques. Signature et vérification concordent automatiquement.

Les deux outils sh POSIX font autorité. Un équivalent Python, `re.sub(r'"sig":"[^"]*",', '', text, count=1)` puis sha256, n'existe que pour les recouper.

Le raisonnement de confiance autour de tout ceci (pourquoi la vérification est sur l'appareil, comment `hardened` échoue en mode fermé) vit dans [[Security and Trust Model]].

---

## baseline.json (la semence d'installation)

Lorsqu'un module vient d'être installé, il devrait déjà être "à jour" pour sa propre version livrée, sans une mise à jour automatique inutile de la version qu'il vient d'installer. C'est ce que fait `baseline.json`.

`baseline.json` est livré **à l'intérieur du zip du module** (sous `vdlu/baseline.json`), pas sur le feed. À une installation neuve, le moteur amorce son enregistrement de "version active" à partir de lui, de sorte que l'appareil naît à jour, sans `from:0` et sans retélécharger ce qu'il possède déjà.

Propriétés clés :

- C'est une **copie sans clé du manifeste signé** pour la version livrée : la même sortie de `vdlu-pack`, laissée non signée (`key_id` et `sig` restent vides).
- Il n'est **pas vérifié**. Le moteur le traite comme une semence locale de confiance parce qu'il est arrivé à l'intérieur du zip flashé, qui est la frontière de confiance d'installation. Seul un manifeste *récupéré depuis le feed* passe par la vérification de signature.
- Parce qu'il n'a besoin d'aucune signature, **la CI peut le générer sans clé**, ce qui maintient la clé de signature entièrement hors de la CI (voir [[Producer]]).
- `vdlu-pack` **exclut `baseline.json` de son propre manifeste**, de sorte que le manifeste ne référence jamais la baseline (ce serait une boucle d'auto-référence : manifeste vers baseline vers manifeste).
- Il est **non fatal s'il est absent**. Sans lui, l'appareil part simplement de `from:0` lors de sa première mise à jour et récupère ce dont il a besoin. Jamais cassé, juste moins optimal.

---

## Blobs

Chaque contenu de fichier distinct est un blob sous `blobs/`, nommé par le **sha256 du contenu original** :

- `blobs/<sha256>` pour un blob brut.
- `blobs/<sha256>.gz` pour un blob compressé en gzip (le gzip n'est conservé que lorsque le fichier fait au moins 4096 octets et que la compression économise au moins 10 pour cent).

Un blob est stocké une fois, dans un seul format. L'adressage par contenu donne la déduplication gratuitement : un contenu inchangé, partagé ou revenu en arrière correspond à un blob qui existe déjà, de sorte que le feed ne grandit que par un contenu réellement nouveau, et l'appareil ne télécharge que les hachages qui lui manquent. L'appareil vérifie le `sha256` de chaque blob téléchargé par rapport au manifeste (après avoir décompressé un blob `gz`) avant de l'utiliser.

---

## Ce qui est exclu du feed, et pourquoi

Le feed porte **uniquement le contenu propre du module**. Un ensemble fixe de chemins en est tenu à l'écart à dessein. `vdlu-pack` applique un prédicat d'exclusion à la fois lors du parcours de l'arborescence et lors du calcul de `delete[]`.

| Exclu | Pourquoi |
|---|---|
| `vdlu/keyring/`, `vdlu/verify/` (la racine de confiance : clés publiques brutes + le binaire vérificateur) | **C'est la raison de sécurité centrale.** L'ancre de confiance est **flash-only**. Si le keyring ou le vérificateur étaient livrables par le feed, un manifeste pourrait écraser la chose même qui le valide. Les tenir hors du fil signifie qu'un manifeste ne peut jamais réécrire l'ancre de confiance sur l'appareil. |
| `vdlu/baseline.json` | C'est une copie du manifeste signé (la semence d'installation) ; la packer serait une boucle d'auto-référence. |
| `.vd/` infrastructure de flashage | Échafaudage de porte de flashage livré dans le zip, jamais appliqué en direct. |
| `update.json`, `update-mmrl.json` | Leur size/sha sont remplis par la CI *après* la construction des zips, de sorte que la copie livrée diffère de toute copie du feed. Les alimenter causerait un fetch fantôme d'un seul fichier à la première mise à jour automatique de chaque installation, et ils sont de toute façon vestigiaux sur l'appareil (le gestionnaire lit le JSON de mise à jour brut distant). |
| `META-INF/`, `customize.sh` (échafaudage d'installeur) | Consommés par le gestionnaire au moment du **flashage** et non conservés dans le module installé. Ce n'est pas du contenu VDLU ; les servir gaspille des blobs et, si l'un changeait entre versions, il serait écrit comme un fichier d'installeur dans le répertoire du module en direct. |
| Compagnons `.sha256` par fichier | Ils appartiennent au seul zip flashable, deviennent périmés après une mise à jour incrémentale, et doubleraient le manifeste. |
| Fichiers dev/doc (`RELEASE.md`, `CLAUDE.md`, `.gitignore`) | Jamais livrés à l'appareil ; les servir gaspille des blobs et brasse le manifeste signé à chaque édition de doc. |

Le raisonnement derrière l'exclusion de la racine de confiance est développé dans [[Security and Trust Model]].

---

## Sémantique de delete[]

`delete[]` indique à l'appareil quels chemins supprimer, de sorte qu'un fichier abandonné entre releases ne persiste pas sur l'appareil comme un orphelin. Il est calculé en passant `--prev <manifest.json précédent>` à `vdlu-pack` : un chemin qui était dans la release précédente et n'est pas dans l'actuelle devient une entrée de suppression.

La règle importante : **les chemins exclus ne sont jamais émis comme suppressions, même avec `--prev`.** Chaque chemin précédent est passé par le même prédicat d'exclusion utilisé lors du parcours de l'arborescence. Si un `--prev` pointe vers un manifeste plus ancien qui listait encore des chemins désormais exclus (un `baseline.json` égaré, `META-INF/*`, une entrée de keyring, et ainsi de suite), ces chemins **ne** sont **pas** transformés en entrées de suppression. Un chemin exclu n'a jamais été du contenu de feed, donc il n'appartient pas à VDLU de le supprimer, et l'appareil ne reçoit jamais l'ordre de retirer un fichier qui n'a pas été servi via le feed. C'est ce qui empêche la liste d'exclusion de jamais se retourner en instruction destructrice.
