> **Languages:** [English](../PRODUCER.md) · [العربية](../ar/PRODUCER.md) · [Čeština](../cs/PRODUCER.md) · [Deutsch](../de/PRODUCER.md) · [Español](../es/PRODUCER.md) · [فارسی](../fa/PRODUCER.md) · Français · [हिन्दी](../hi/PRODUCER.md) · [Bahasa Indonesia](../id/PRODUCER.md) · [Italiano](../it/PRODUCER.md) · [日本語](../ja/PRODUCER.md) · [한국어](../ko/PRODUCER.md) · [Nederlands](../nl/PRODUCER.md) · [Polski](../pl/PRODUCER.md) · [Português](../pt/PRODUCER.md) · [Русский](../ru/PRODUCER.md) · [Svenska](../sv/PRODUCER.md) · [ไทย](../th/PRODUCER.md) · [Türkçe](../tr/PRODUCER.md) · [Українська](../uk/PRODUCER.md) · [Tiếng Việt](../vi/PRODUCER.md) · [中文](../zh/PRODUCER.md)

---

# Couche producer + signature de VDLU

Construit la livraison adressée par contenu (manifeste + blobs) pour un module et la signe.
Se conforme à [`INTERFACES.md`](INTERFACES.md) §3/§6/§7.

| outil | tourne sur | langage | tâche |
|---|---|---|---|
| `producer/vdlu-pack` | PC / CI | python3 | parcourt l'arbre final du module -> `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | PC | sh + openssl | paire de clés ed25519 (`<id>.pem` priv, `<id>.pub` PEM, `<id>.pub.raw` RAW 32B pour le keyring slim) |
| `producer/vdlu-sign` | PC | sh + openssl | injecte `key_id` + `sig` dans un manifeste, in place |
| `engine/vdlu-verify` | **appareil** | sh + ed25519-mini | vérifie `sig` via l'ed25519-mini embarqué ; keyring = pubkey RAW 32B (PAS d'openssl sur l'appareil) |

## Pipeline

```sh
# 1. one-time: a signing key. Keep the .pem off every device and off any repo push.
producer/vdlu-keygen release-2026 ./keys

# 2. each release: pack the final tree (same tree the .zip ships, post-whitelist).
producer/vdlu-pack  ./module_tree  ./out  demo 106 --version-name v106 --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev

# 3. sign the manifest in place.
producer/vdlu-sign  ./out/manifest.json  ./keys/release-2026.pem  release-2026

# 4. publish ./out/{manifest.json,blobs/} to <source> (Pages batch for public; rsync for private).
#    The slim device keyring holds ./keys/release-2026.pub.raw as keyring/release-2026.pub (RAW 32B).
```

`vdlu-pack` est adressé par contenu et déduplicant : un blob dont le `<sha256>` existe déjà n'est pas
réécrit, donc la publication est incrémentale et le contenu inchangé / reverti n'est jamais re-poussé.

### Décision de `enc` (vdlu-pack)

`sha256` est **toujours** du contenu original (non compressé), `enc` ne fait que nommer comment le blob est stocké.

- `gz` quand `size >= 4096` **et** que gzip (`-9 -n`, déterministe) économise au moins 10% (`comp <= raw*0.90`).
- `raw` sinon (petit texte que le gzip de HTTP couvre déjà, ou données déjà incompressibles).
- gzip manquant sur l'hôte de build -> tout en `raw` (n'échoue jamais).

Un blob est stocké une fois, dans un format : `blobs/<sha256>` (raw) ou `blobs/<sha256>.gz` (gz). L'appareil
décompresse avec toybox `gunzip` (toujours présent), donc aucun zstd n'est empaqueté.

### Décision de `class` (vdlu-pack) - taxonomie de reboot

Dérivée du path (INTERFACES §3, doc §4). Défauts seulement, une règle de path ne dégrade jamais `reboot`->`live`.

| class | détectée par | appliquée |
|---|---|---|
| `reboot` | `system/**`, `zygisk/**/*.so`, `*.rule` | mise en scène `.vdlu-new`, swap au boot |
| `soft` | `service.sh` / `post-fs-data.sh` / `boot-completed.sh` racine | écrite en vivant, tourne au prochain boot |
| `live` | tout le reste (webroot, bin, lib, confs, module.prop, ...) | écrite en vivant, atomique |

Les symlinks ne sont **pas suivis** (ne fuient jamais de contenu hors de l'arbre, p. ex. un lien vers
`/etc/shadow`) et sont sautés avec un avertissement, puisque le schéma du manifeste n'a pas de type symlink.
Les fichiers non réguliers (dirs, fifos, devices) sont sautés. `built` respecte `SOURCE_DATE_EPOCH` pour des
manifestes reproductibles.

### Baseline (la graine d'installation) - non signée, sans clé

`baseline.json` (livré à `vdlu/baseline.json` dans le zip du module) sème `current.json` à une installation
fraîche pour que l'appareil naisse "à jour" (pas de from:0, pas de re-fetch). L'engine le traite comme une
**graine locale de confiance** (elle est arrivée dans le zip flashé, qui est la frontière de confiance de
l'installation) et **ne vérifie PAS sa signature** - seul le manifeste RÉCUPÉRÉ du feed passe par `vdlu-verify`.
Donc la baseline n'a besoin d'**aucune clé** : c'est juste la sortie de `vdlu-pack` sur l'arbre livré (non signé ;
`sig`/`key_id` restent vides). Une CI peut donc la générer **sans clé**, gardant la clé de signature 100% hors de
la CI - seul le FEED publié est signé (opérateur, localement). `vdlu-pack` exclut `baseline.json` de son propre
manifeste (anti auto-référence). Non fatal si absent : l'appareil part simplement de from:0 à la première mise à
jour, jamais cassé.

## Canonicalisation (le point de convergence)

`vdlu-sign` et `engine/vdlu-verify` doivent dériver les **mêmes octets** d'un manifeste, sur deux
runtimes différents (openssl du PC vs toybox de l'appareil). La règle est délibérément une
transformation d'octets, pas une re-sérialisation JSON, donc elle n'a besoin d'aucune librairie JSON sur
l'appareil :

1. `vdlu-pack` écrit `manifest.json` **compact, clés triées, UTF-8**
   (`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`), incluant toujours
   les champs `key_id` et `sig` (placeholders de chaîne vide jusqu'à la signature). C'est la forme de stockage
   canonique.
2. **Forme canonique = ce texte avec le champ `"sig"` retiré.** Comme les clés sont triées, `sig`
   apparaît toujours comme `,"sig":"<value>",` encadré par `"schema"` (avant) et `"version"` (après),
   tous deux toujours présents. Le retirer laisse `...,"schema":N,"version":...` bien formé.
   JSON échappe chaque `"` à l'intérieur des valeurs de chaîne en `\"`, donc le token structurel `"sig":"` est
   non ambigu même face à un nom de fichier qui contient littéralement `"sig":"` (testé).
3. Le message signé/vérifié est le **sha256 hex** (64 caractères ASCII, sans newline) de la forme
   canonique. ed25519 sur ce hex (`openssl pkeyutl -sign/-verify -rawin`).

Le retrait en sh POSIX (fonction identique dans les deux outils, sans `sed`/`jq`) :

```sh
# $1 = full manifest text (trailing newline already stripped by $(cat ...))
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

`key_id` fait partie de la forme canonique (seul `sig` est retiré), `vdlu-sign` fixe `key_id` **avant** de
hasher. Le placeholder de valeur vide (`"sig":""`, à la signature) ou rempli (à la vérification) donne les
octets canoniques identiques, donc signature et verify s'accordent par construction.

Python le reproduit comme `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)` puis sha256 - utilisé
seulement pour le cross-check, les producteurs faisant autorité sont les deux outils sh.

## Signature (ed25519)

- `vdlu-keygen` (PC) : `openssl genpkey -algorithm ed25519` (priv `0600`) + `openssl pkey -pubout` (pub **PEM**,
  pour la signature/openssl) + `openssl pkey -pubout -outform DER | tail -c 32` -> **`.pub.raw` (RAW 32B)** (le DER
  SPKI ed25519 est un préfixe de 12 octets + la clé de 32 octets, donc `tail -c 32` EST la clé). Il émet les DEUX.
- `vdlu-sign` (PC) : `openssl pkeyutl -sign -rawin` sur le sha256 hex canonique, signature stockée en base64.
- `vdlu-verify` (**appareil, slim**) : `ed25519-mini <pubkey32> <msg> <sig64>` - lit le keyring comme la pubkey
  **RAW 32B**, PAS d'openssl sur l'appareil. `key_id` est path-sanitized (pas de `/`, `.`, `..`, `"`). 🚨 Le keyring
  livre le **`.pub.raw` (32B)**, jamais le `.pub` PEM (113B) : le PEM est PC-side seulement et `ed25519-mini` ne peut
  pas le lire.

Modèle de confiance (INTERFACES §6, doc §11/§13) : `profile=hardened` (public) rend verify obligatoire - une
signature échouée ou absente abandonne la mise à jour. `profile=trusted` (privé, source stagée par SSH) traite
verify comme best-effort, mais le sha256 de chaque blob est vérifié de toute façon.

## Keyring + rotation

Le keyring est un répertoire de fichiers `<key_id>.pub`, chacun la pubkey ed25519 **RAW 32B** (du `.pub.raw` de
`keygen`), PAS PEM - `ed25519-mini` lit 32 octets raw. Livre la pubkey raw actuelle **et** la précédente
(doc §13) pour qu'une clé rotée ne brique pas les anciennes installations. `vdlu-sign` avec le nouveau `key_id` et
l'appareil choisissant `<keyring>/<key_id>.pub` (raw) est tout le mécanisme de rotation - aucun changement
d'engine. Le keyring est **stable** à travers les releases (seule la rotation de clé le change) : un re-vendor
doit le **vérifier-pas-copier** et ne jamais l'écraser avec le `.pub` PEM du PC-side.

**Les keyrings multiclés DOIVENT épingler la clé du module.** L'engine restreint quel `key_id` peut signer un MODULE-UPDATE à l'allowlist `key_id` de la config (INTERFACES §5/§6), vérifiée fail-closed avant que la pubkey soit sélectionnée. Un keyring à une clé est sûr par défaut (cette unique clé est acceptée). Mais un module dont le keyring porte AUSSI une clé de moindre confiance - p. ex. une clé de fingerprint-feed à côté de la clé de release - est rejeté tant que son `config` ne déclare pas la clé du module, p. ex. `key_id=vd-2026` (séparées par des virgules pour la rotation, p. ex. `key_id=vd-2026,vd-2027`). Cela empêche une clé de moindre confiance ayant fuité de signer une mise à jour root flashless.

`vdlu-pack` **exclut le keyring et les binaires `verify/` du feed** (la racine de confiance est flash uniquement, jamais servie sur le réseau), aux côtés de `baseline.json`, de l'échafaudage de l'installeur (`META-INF/`, `customize.sh`), de la porte de flash `.vd/`, des `update.json`/`update-mmrl.json` remplis par la CI, et des compagnons `.sha256` par fichier. Seul le contenu propre du module est actualisable par le feed, donc un manifeste ne peut jamais réécrire l'ancre de confiance sur l'appareil.

<!-- doc-footer -->

---

> _Cette documentation a été générée avec Claude (Anthropic) et est maintenue par VD171. Les corrections et améliorations sont les bienvenues, voir [CONTRIBUTING.md](CONTRIBUTING.md)._
