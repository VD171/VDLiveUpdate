> **Languages:** [English](../PRODUCER.md) · [العربية](../ar/PRODUCER.md) · [Čeština](../cs/PRODUCER.md) · [Deutsch](../de/PRODUCER.md) · [Español](../es/PRODUCER.md) · [فارسی](../fa/PRODUCER.md) · Français · [हिन्दी](../hi/PRODUCER.md) · [Bahasa Indonesia](../id/PRODUCER.md) · [Italiano](../it/PRODUCER.md) · [日本語](../ja/PRODUCER.md) · [한국어](../ko/PRODUCER.md) · [Nederlands](../nl/PRODUCER.md) · [Polski](../pl/PRODUCER.md) · [Português](../pt/PRODUCER.md) · [Русский](../ru/PRODUCER.md) · [Svenska](../sv/PRODUCER.md) · [ไทย](../th/PRODUCER.md) · [Türkçe](../tr/PRODUCER.md) · [Українська](../uk/PRODUCER.md) · [Tiếng Việt](../vi/PRODUCER.md) · [中文](../zh/PRODUCER.md)

---

# Couche producer + signature de VDLU

Construit la livraison adressee par contenu (manifeste + blobs) pour un module et la signe.
Se conforme a [`INTERFACES.md`](INTERFACES.md) §3/§6/§7.

| outil | tourne sur | langage | tache |
|---|---|---|---|
| `producer/vdlu-pack` | PC / CI | python3 | parcourt l'arbre final du module -> `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | PC | sh + openssl | paire de cles ed25519 (`<id>.pem` priv, `<id>.pub` PEM, `<id>.pub.raw` RAW 32B pour le keyring slim) |
| `producer/vdlu-sign` | PC | sh + openssl | injecte `key_id` + `sig` dans un manifeste, in place |
| `engine/vdlu-verify` | **appareil** | sh + ed25519-mini | verifie `sig` via l'ed25519-mini embarque ; keyring = pubkey RAW 32B (PAS d'openssl sur l'appareil) |

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

`vdlu-pack` est adresse par contenu et deduplicant : un blob dont le `<sha256>` existe deja n'est pas
reecrit, donc la publication est incrementale et le contenu inchange / reverti n'est jamais re-pousse.

### Decision de `enc` (vdlu-pack)

`sha256` est **toujours** du contenu original (non compresse) ; `enc` ne fait que nommer comment le blob est stocke.

- `gz` quand `size >= 4096` **et** que gzip (`-9 -n`, deterministe) economise au moins 10% (`comp <= raw*0.90`).
- `raw` sinon (petit texte que le gzip de HTTP couvre deja, ou donnees deja incompressibles).
- gzip manquant sur l'hote de build -> tout en `raw` (n'echoue jamais).

Un blob est stocke une fois, dans un format : `blobs/<sha256>` (raw) ou `blobs/<sha256>.gz` (gz). L'appareil
decompresse avec toybox `gunzip` (toujours present), donc aucun zstd n'est empaquete.

### Decision de `class` (vdlu-pack) - taxonomie de reboot

Derivee du path (INTERFACES §3, doc §4). Defauts seulement ; une regle de path ne degrade jamais `reboot`->`live`.

| class | detectee par | appliquee |
|---|---|---|
| `reboot` | `system/**`, `zygisk/**/*.so`, `*.rule` | mise en scene `.vdlu-new`, swap au boot |
| `soft` | `service.sh` / `post-fs-data.sh` / `boot-completed.sh` racine | ecrite en vivant, tourne au prochain boot |
| `live` | tout le reste (webroot, bin, lib, confs, module.prop, ...) | ecrite en vivant, atomique |

Les symlinks ne sont **pas suivis** (ne fuient jamais de contenu hors de l'arbre, p. ex. un lien vers
`/etc/shadow`) et sont sautes avec un avertissement, puisque le schema du manifeste n'a pas de type symlink.
Les fichiers non reguliers (dirs, fifos, devices) sont sautes. `built` respecte `SOURCE_DATE_EPOCH` pour des
manifestes reproductibles.

### Baseline (la graine d'installation) - non signee, sans cle

`baseline.json` (livre a `vdlu/baseline.json` dans le zip du module) seme `current.json` a une installation
fraiche pour que l'appareil naisse "a jour" (pas de from:0, pas de re-fetch). L'engine le traite comme une
**graine locale de confiance** (elle est arrivee dans le zip flashe, qui est la frontiere de confiance de
l'installation) et **ne verifie PAS sa signature** - seul le manifeste RECUPERE du feed passe par `vdlu-verify`.
Donc la baseline n'a besoin d'**aucune cle** : c'est juste la sortie de `vdlu-pack` sur l'arbre livre (non signe ;
`sig`/`key_id` restent vides). Une CI peut donc la generer **sans cle**, gardant la cle de signature 100% hors de
la CI - seul le FEED publie est signe (operateur, localement). `vdlu-pack` exclut `baseline.json` de son propre
manifeste (anti auto-reference). Non fatal si absent : l'appareil part simplement de from:0 a la premiere mise a
jour, jamais casse.

## Canonicalisation (le point de convergence)

`vdlu-sign` et `engine/vdlu-verify` doivent deriver les **memes octets** d'un manifeste, sur deux
runtimes differents (openssl du PC vs toybox + openssl de l'appareil). La regle est deliberement une
transformation d'octets, pas une re-serialisation JSON, donc elle n'a besoin d'aucune librairie JSON sur
l'appareil :

1. `vdlu-pack` ecrit `manifest.json` **compact, cles triees, UTF-8**
   (`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`), incluant toujours
   les champs `key_id` et `sig` (placeholders de chaine vide jusqu'a la signature). C'est la forme de stockage
   canonique.
2. **Forme canonique = ce texte avec le champ `"sig"` retire.** Comme les cles sont triees, `sig`
   apparait toujours comme `,"sig":"<value>",` encadre par `"schema"` (avant) et `"version"` (apres),
   tous deux toujours presents. Le retirer laisse `...,"schema":N,"version":...` bien forme.
   JSON echappe chaque `"` a l'interieur des valeurs de chaine en `\"`, donc le token structurel `"sig":"` est
   non ambigu meme face a un nom de fichier qui contient litteralement `"sig":"` (teste).
3. Le message signe/verifie est le **sha256 hex** (64 caracteres ASCII, sans newline) de la forme
   canonique. ed25519 sur ce hex (`openssl pkeyutl -sign/-verify -rawin`).

Le retrait en sh POSIX (fonction identique dans les deux outils, sans `sed`/`jq`) :

```sh
# $1 = full manifest text (trailing newline already stripped by $(cat ...))
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

`key_id` fait partie de la forme canonique (seul `sig` est retire) ; `vdlu-sign` fixe `key_id` **avant** de
hasher. Le placeholder de valeur vide (`"sig":""`, a la signature) ou rempli (a la verification) donne les
octets canoniques identiques, donc signature et verify s'accordent par construction.

Python le reproduit comme `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)` puis sha256 - utilise
seulement pour le cross-check ; les producteurs faisant autorite sont les deux outils sh.

## Signature (ed25519)

- `vdlu-keygen` (PC) : `openssl genpkey -algorithm ed25519` (priv `0600`) + `openssl pkey -pubout` (pub **PEM**,
  pour la signature/openssl) + `openssl pkey -pubout -outform DER | tail -c 32` -> **`.pub.raw` (RAW 32B)** (le DER
  SPKI ed25519 est un prefixe de 12 octets + la cle de 32 octets, donc `tail -c 32` EST la cle). Il emet les DEUX.
- `vdlu-sign` (PC) : `openssl pkeyutl -sign -rawin` sur le sha256 hex canonique ; signature stockee en base64.
- `vdlu-verify` (**appareil, slim**) : `ed25519-mini <pubkey32> <msg> <sig64>` - lit le keyring comme la pubkey
  **RAW 32B**, PAS d'openssl sur l'appareil. `key_id` est path-sanitized (pas de `/`, `.`, `..`, `"`). 🚨 Le keyring
  livre le **`.pub.raw` (32B)**, jamais le `.pub` PEM (113B) : le PEM est PC-side seulement et `ed25519-mini` ne peut
  pas le lire.

Modele de confiance (INTERFACES §6, doc §11/§13) : `profile=hardened` (public) rend verify obligatoire - une
signature echouee ou absente abandonne la mise a jour. `profile=trusted` (prive, source stagee par SSH) traite
verify comme best-effort, mais le sha256 de chaque blob est verifie de toute facon.

## Keyring + rotation

Le keyring est un repertoire de fichiers `<key_id>.pub`, chacun la pubkey ed25519 **RAW 32B** (du `.pub.raw` de
`keygen`), PAS PEM - `ed25519-mini` lit 32 octets raw. Livre la pubkey raw actuelle **et** la precedente
(doc §13) pour qu'une cle rotee ne brique pas les anciennes installations. `vdlu-sign` avec le nouveau `key_id` et
l'appareil choisissant `<keyring>/<key_id>.pub` (raw) est tout le mecanisme de rotation - aucun changement
d'engine. Le keyring est **stable** a travers les releases (seule la rotation de cle le change) : un re-vendor
doit le **verifier-pas-copier** et ne jamais l'ecraser avec le `.pub` PEM du PC-side.

<!-- doc-footer -->

---

> _Cette documentation a été générée avec Claude (Anthropic) et est maintenue par VD171. Les corrections et améliorations sont les bienvenues ; voir [CONTRIBUTING.md](CONTRIBUTING.md)._
