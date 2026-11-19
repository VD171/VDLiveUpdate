> **Languages:** [English](../ENGINE.md) · [العربية](../ar/ENGINE.md) · [Čeština](../cs/ENGINE.md) · [Deutsch](../de/ENGINE.md) · [Español](../es/ENGINE.md) · [فارسی](../fa/ENGINE.md) · Français · [हिन्दी](../hi/ENGINE.md) · [Bahasa Indonesia](../id/ENGINE.md) · [Italiano](../it/ENGINE.md) · [日本語](../ja/ENGINE.md) · [한국어](../ko/ENGINE.md) · [Nederlands](../nl/ENGINE.md) · [Polski](../pl/ENGINE.md) · [Português](../pt/ENGINE.md) · [Русский](../ru/ENGINE.md) · [Svenska](../sv/ENGINE.md) · [ไทย](../th/ENGINE.md) · [Türkçe](../tr/ENGINE.md) · [Українська](../uk/ENGINE.md) · [Tiếng Việt](../vi/ENGINE.md) · [中文](../zh/ENGINE.md)

---

# Engine VDLU (`update.sh`)

Client de mise à jour flashless et incrémentale pour les modules KSU/Magisk. Implémente le cycle
`DIFF -> FETCH -> APPLY -> COMMIT` comme une transaction reprenable. Se conforme à `INTERFACES.md` (la loi
de convergence).

sh POSIX pur (mksh/busybox/toybox). **SLIM :** il dépend seulement de toybox (`sha256sum`/`gzip`/`base64`/`date`) +
l'`ed25519-mini` embarqué (verify ed25519 ; **pas d'openssl sur l'appareil**) + un `curl` statique **récupéré**
à la première mise à jour https (la WebUI fait le `fetch()`, le persiste en Tier-2, et `install-tool` vérifie sa
signature+hash AVANT de l'utiliser). `file://` n'a pas besoin de curl. Zéro dépendance à `jq`.

## Invocation

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = ok ; `rc != 0` = erreur (raison sur stderr). `vdlu-verify` est livré par un autre composant
(signature dans `INTERFACES.md §6`) ; l'engine ne fait que l'appeler.

| cmd | fait |
|---|---|
| `check` | DIFF en lecture seule ; imprime `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}` ; ne change rien |
| `run` | cycle LIVE complet + met en scène REBOOT-hard ; respecte `cancel` ; progression dans `journal.json` |
| `resume` | reprend la transaction en attente (`target.json`) depuis la phase courante ; idempotent ; ne fait **pas** le swap du `.so` |
| `boot` | mode pré-zygote : resume **+** swappe les `staged/*.vdlu-new` → ferme `PENDING_REBOOT`→`DONE`. Sans transaction en attente, il lance un cycle neuf et applique tout (y compris le `.so`) en un seul boot |
| `status` | imprime `journal.json` (ou `{"state":"idle"}`) |
| `cancel` | crée `$VDLU_DIR/cancel` ; un `run` en cours s'arrête au prochain point sûr |

## Machine à états (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE` seulement une fois qu'un re-hash de TOUT correspond. Si un REBOOT-hard a été mis en scène ⇒
`PENDING_REBOOT` (jamais un `DONE` factice). `ERROR` à tout échec, sans corrompre le module (les fichiers LIVE
appliqués sont revertis depuis `rollback/<v>/` ; rien de "à moitié appliqué qui ment là-dessus"). Sortie bénigne
de la phase `fetch` : **`DEFERRED`** - le téléchargement a été différé par `net_policy` (réseau non autorisé) ;
plan/target persistent et il reprend au prochain check/boot (la WebUI montre un toast info bleu "en attente du
réseau X", pas une erreur).

## Garanties de rigueur

- **FETCH :** contrôlé par `net_policy` (any/wifi/mobile ; http/https seulement, `file://` jamais) - un réseau
  non autorisé ⇒ `DEFERRED` (reprenable), sans dépenser de données. Ne télécharge que ce qui manque dans
  `<sha>.part` (curl avec `--connect-timeout` + `--speed-time`, ne se bloque jamais), décompresse `gz` (toybox
  `gunzip`), vérifie `sha256sum` == manifeste, `mv` atomique vers `blobs/<sha>`. Un blob cache+ok est sauté. Il
  peut semer le blob depuis un fichier local inchangé (dedup/offline). **3 échecs sur le même blob = la phase
  abandonne sans rien appliquer.** Il ne devient `FETCHED` qu'avec TOUS les blobs du plan présents+vérifiés.
- **APPLY** (seulement depuis `FETCHED`) : `live`/`soft` → sauvegarde vers `rollback/<v>/` → `.vdlu-tmp` → `chmod` → verify →
  `rename` atomique. `reboot` → matérialise dans `staged/<path>.vdlu-new` (ne touche PAS l'inode vivant).
  `delete[]` → sauvegarde → suppression. Idempotent (un fichier déjà au hash cible est sauté).
- **COMMIT :** re-hash de chaque `live`/`soft` ; seulement alors il écrit `current.json`. Avec des fichiers mis
  en scène ⇒ `PENDING_REBOOT`. `boot` fait `mv -f staged/....vdlu-new $MODULE_DIR/<path>` (pré-zygote) +
  re-vérifie + `DONE`.
- **cancel :** vérifie entre les fichiers (point sûr) ; supprime le `.vdlu-tmp`/`.part` en vol, efface `cancel`,
  laisse le journal reprenable (`cancelled:true`, `error:null`).
- **mkdir-lock `$VDLU_DIR/lock.d`** sérialise (flock est inutilisable sur toybox ; récupération du stale par
  PID). Le retry de boot PATIENT ne tient pas le lock pendant l'attente (`acquire_lock_try`+release entre les
  essais) ni un wakelock - sans danger pour la batterie. Un crash/réseau/reboot en cours de route → `resume`/`boot`
  continue.
- **profile=hardened** ⇒ `vdlu-verify` obligatoire sur le manifeste AVANT usage ; échec = abandon ; downgrade
  bloqué (version monotone). **trusted** ⇒ verify est best-effort, mais le hash de chaque blob est TOUJOURS vérifié.
- Dégrade avec grâce : binaire manquant / réseau coupé / disque plein → une erreur claire sur stderr + `state:ERROR`
  dans le journal, sans corrompre le module.

## Parsing JSON sans jq

Un aplatisseur style gron en `awk` (POSIX pur : `substr`/`index`/`gsub`/`split`/`printf` + locals passés comme
paramètres) tokenise le manifeste caractère par caractère et émet une ligne `path<TAB>value` par feuille scalaire
(`files/0/sha256<TAB>ab..`, `version<TAB>6`, `delete/0<TAB>etc/x`). Robuste face à du JSON compact OU
pretty-printed. Le `sh` le consomme avec `grep`/`cut` ; le plan par fichier est réassemblé dans un 2e `awk` en TSV
(`class st mode enc sha size path`), qui devient `$VDLU_DIR/plan.tsv`.

## Fichiers d'état (dans `$VDLU_DIR`, Tier-2)

| fichier | rôle |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`boot_retry_*`/… ; voir INTERFACES §5) |
| `current.json` | manifeste de la version ACTIVE (base du diff) ; absent = jamais mis à jour |
| `target.json` | manifeste épinglé de la transaction en vol (présence = transaction active) ; devient `current.json` au `DONE` |
| `plan.tsv` / `plan.del` | plan + progression par fichier (st) / paths à supprimer |
| `journal.json` | progression pour la WebUI (régénérée à chaque transition) |
| `blobs/<sha256>` | cache du contenu original vérifié |
| `rollback/<version>/<path>` | sauvegarde des fichiers écrasés (undo ; garde les 3 derniers) |
| `staged/<path>.vdlu-new` | REBOOT-hard en attente de swap au boot |
| `lock.d/` | mkdir-lock (flock inutilisable sur toybox ; récupération du stale par PID) |
| `tools/<abi>/curl` | curl statique récupéré (bootstrap slim) ; persiste à travers les mises à jour |
| `cancel` | demande d'annulation |

<!-- doc-footer -->

---

> _Cette documentation a été générée avec Claude (Anthropic) et est maintenue par VD171. Les corrections et améliorations sont les bienvenues ; voir [CONTRIBUTING.md](CONTRIBUTING.md)._
