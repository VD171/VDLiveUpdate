> **Languages:** [English](../ENGINE.md) · [العربية](../ar/ENGINE.md) · [Čeština](../cs/ENGINE.md) · [Deutsch](../de/ENGINE.md) · [Español](../es/ENGINE.md) · [فارسی](../fa/ENGINE.md) · Français · [हिन्दी](../hi/ENGINE.md) · [Bahasa Indonesia](../id/ENGINE.md) · [Italiano](../it/ENGINE.md) · [日本語](../ja/ENGINE.md) · [한국어](../ko/ENGINE.md) · [Nederlands](../nl/ENGINE.md) · [Polski](../pl/ENGINE.md) · [Português](../pt/ENGINE.md) · [Русский](../ru/ENGINE.md) · [Svenska](../sv/ENGINE.md) · [ไทย](../th/ENGINE.md) · [Türkçe](../tr/ENGINE.md) · [Українська](../uk/ENGINE.md) · [Tiếng Việt](../vi/ENGINE.md) · [中文](../zh/ENGINE.md)

---

# Engine VDLU (`update.sh`)

Client de mise a jour flashless et incrementale pour les modules KSU/Magisk. Implemente le cycle
`DIFF -> FETCH -> APPLY -> COMMIT` comme une transaction reprenable. Se conforme a `INTERFACES.md` (la loi
de convergence).

sh POSIX pur (mksh/busybox/toybox). **SLIM :** il depend seulement de toybox (`sha256sum`/`gzip`/`base64`/`date`) +
l'`ed25519-mini` embarque (verify ed25519 ; **pas d'openssl sur l'appareil**) + un `curl` statique **recupere**
a la premiere mise a jour https (la WebUI fait le `fetch()`, le persiste en Tier-2, et `install-tool` verifie sa
signature+hash AVANT de l'utiliser). `file://` n'a pas besoin de curl. Zero dependance a `jq`.

## Invocation

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = ok ; `rc != 0` = erreur (raison sur stderr). `vdlu-verify` est livre par un autre composant
(signature dans `INTERFACES.md §6`) ; l'engine ne fait que l'appeler.

| cmd | fait |
|---|---|
| `check` | DIFF en lecture seule ; imprime `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}` ; ne change rien |
| `run` | cycle LIVE complet + met en scene REBOOT-hard ; respecte `cancel` ; progression dans `journal.json` |
| `resume` | reprend la transaction en attente (`target.json`) depuis la phase courante ; idempotent ; ne fait **pas** le swap du `.so` |
| `boot` | mode pre-zygote : resume **+** swappe les `staged/*.vdlu-new` → ferme `PENDING_REBOOT`→`DONE`. Sans transaction en attente, il lance un cycle neuf et applique tout (y compris le `.so`) en un seul boot |
| `status` | imprime `journal.json` (ou `{"state":"idle"}`) |
| `cancel` | cree `$VDLU_DIR/cancel` ; un `run` en cours s'arrete au prochain point sur |

## Machine a etats (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE` seulement une fois qu'un re-hash de TOUT correspond. Si un REBOOT-hard a ete mis en scene ⇒
`PENDING_REBOOT` (jamais un `DONE` factice). `ERROR` a tout echec, sans corrompre le module (les fichiers LIVE
appliques sont revertis depuis `rollback/<v>/` ; rien de "a moitie applique qui ment la-dessus"). Sortie benigne
de la phase `fetch` : **`DEFERRED`** - le telechargement a ete differe par `net_policy` (reseau non autorise) ;
plan/target persistent et il reprend au prochain check/boot (la WebUI montre un toast info bleu "en attente du
reseau X", pas une erreur).

## Garanties de rigueur

- **FETCH :** controle par `net_policy` (any/wifi/mobile ; http/https seulement, `file://` jamais) - un reseau
  non autorise ⇒ `DEFERRED` (reprenable), sans depenser de donnees. Ne telecharge que ce qui manque dans
  `<sha>.part` (curl avec `--connect-timeout` + `--speed-time`, ne se bloque jamais), decompresse `gz` (toybox
  `gunzip`), verifie `sha256sum` == manifeste, `mv` atomique vers `blobs/<sha>`. Un blob cache+ok est saute. Il
  peut semer le blob depuis un fichier local inchange (dedup/offline). **3 echecs sur le meme blob = la phase
  abandonne sans rien appliquer.** Il ne devient `FETCHED` qu'avec TOUS les blobs du plan presents+verifies.
- **APPLY** (seulement depuis `FETCHED`) : `live`/`soft` → sauvegarde vers `rollback/<v>/` → `.vdlu-tmp` → `chmod` → verify →
  `rename` atomique. `reboot` → materialise dans `staged/<path>.vdlu-new` (ne touche PAS l'inode vivant).
  `delete[]` → sauvegarde → suppression. Idempotent (un fichier deja au hash cible est saute).
- **COMMIT :** re-hash de chaque `live`/`soft` ; seulement alors il ecrit `current.json`. Avec des fichiers mis
  en scene ⇒ `PENDING_REBOOT`. `boot` fait `mv -f staged/....vdlu-new $MODULE_DIR/<path>` (pre-zygote) +
  re-verifie + `DONE`.
- **cancel :** verifie entre les fichiers (point sur) ; supprime le `.vdlu-tmp`/`.part` en vol, efface `cancel`,
  laisse le journal reprenable (`cancelled:true`, `error:null`).
- **mkdir-lock `$VDLU_DIR/lock.d`** serialise (flock est inutilisable sur toybox ; recuperation du stale par
  PID). Le retry de boot PATIENT ne tient pas le lock pendant l'attente (`acquire_lock_try`+release entre les
  essais) ni un wakelock - sans danger pour la batterie. Un crash/reseau/reboot en cours de route → `resume`/`boot`
  continue.
- **profile=hardened** ⇒ `vdlu-verify` obligatoire sur le manifeste AVANT usage ; echec = abandon ; downgrade
  bloque (version monotone). **trusted** ⇒ verify est best-effort, mais le hash de chaque blob est TOUJOURS verifie.
- Degrade avec grace : binaire manquant / reseau coupe / disque plein → une erreur claire sur stderr + `state:ERROR`
  dans le journal, sans corrompre le module.

## Parsing JSON sans jq

Un aplatisseur style gron en `awk` (POSIX pur : `substr`/`index`/`gsub`/`split`/`printf` + locals passes comme
parametres) tokenise le manifeste caractere par caractere et emet une ligne `path<TAB>value` par feuille scalaire
(`files/0/sha256<TAB>ab..`, `version<TAB>6`, `delete/0<TAB>etc/x`). Robuste face a du JSON compact OU
pretty-printed. Le `sh` le consomme avec `grep`/`cut` ; le plan par fichier est reassemble dans un 2e `awk` en TSV
(`class st mode enc sha size path`), qui devient `$VDLU_DIR/plan.tsv`.

## Fichiers d'etat (dans `$VDLU_DIR`, Tier-2)

| fichier | role |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`boot_retry_*`/… ; voir INTERFACES §5) |
| `current.json` | manifeste de la version ACTIVE (base du diff) ; absent = jamais mis a jour |
| `target.json` | manifeste epingle de la transaction en vol (presence = transaction active) ; devient `current.json` au `DONE` |
| `plan.tsv` / `plan.del` | plan + progression par fichier (st) / paths a supprimer |
| `journal.json` | progression pour la WebUI (regeneree a chaque transition) |
| `blobs/<sha256>` | cache du contenu original verifie |
| `rollback/<version>/<path>` | sauvegarde des fichiers ecrases (undo ; garde les 3 derniers) |
| `staged/<path>.vdlu-new` | REBOOT-hard en attente de swap au boot |
| `lock.d/` | mkdir-lock (flock inutilisable sur toybox ; recuperation du stale par PID) |
| `tools/<abi>/curl` | curl statique recupere (bootstrap slim) ; persiste a travers les mises a jour |
| `cancel` | demande d'annulation |

<!-- doc-footer -->

---

> _Cette documentation a été générée avec Claude (Anthropic) et est maintenue par VD171. Les corrections et améliorations sont les bienvenues ; voir [CONTRIBUTING.md](CONTRIBUTING.md)._
