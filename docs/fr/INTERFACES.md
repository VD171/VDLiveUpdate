> **Languages:** [English](../INTERFACES.md) · [العربية](../ar/INTERFACES.md) · [Čeština](../cs/INTERFACES.md) · [Deutsch](../de/INTERFACES.md) · [Español](../es/INTERFACES.md) · [فارسی](../fa/INTERFACES.md) · Français · [हिन्दी](../hi/INTERFACES.md) · [Bahasa Indonesia](../id/INTERFACES.md) · [Italiano](../it/INTERFACES.md) · [日本語](../ja/INTERFACES.md) · [한국어](../ko/INTERFACES.md) · [Nederlands](../nl/INTERFACES.md) · [Polski](../pl/INTERFACES.md) · [Português](../pt/INTERFACES.md) · [Русский](../ru/INTERFACES.md) · [Svenska](../sv/INTERFACES.md) · [ไทย](../th/INTERFACES.md) · [Türkçe](../tr/INTERFACES.md) · [Українська](../uk/INTERFACES.md) · [Tiếng Việt](../vi/INTERFACES.md) · [中文](../zh/INTERFACES.md)

---

# VDLU - Contrat d'interface (la couture entre les composants)

**Loi de convergence :** chaque composant se conforme a ce fichier. Les pieces issues de 4 agents doivent
**s'emboiter** - les signatures CLI, les noms de fichier et les cles JSON ci-dessous sont **immuables** (un
changement implique de s'aligner ici d'abord).

Principes herites des repos : **sh POSIX pur** sur l'appareil (pas de bashismes ; tourne avec toybox/busybox +
`sha256sum`/`gzip`/`base64` de toybox + le `curl` recupere + le `ed25519-mini` embarque - mince, sans bundle de
binaires), **zero commentaire gratuit**, **toujours release**, **rigueur face a l'echec** (transaction
reprenable, rien de faussement "termine", rien de perdu), **rien de relache**.

---

## 1. Disposition de l'etat (Tier-2, hors du repertoire du module)

```
$VDLU_DIR = /data/adb/<module>/vdlu
  config               # key=value (§5)
  current.json         # manifest of the ACTIVE version (diff base); absent = never updated
  journal.json         # transaction in progress (§4); absent = idle
  cancel               # presence = cancel request (WebUI creates it; engine deletes it on stop)
  lock.d/              # mkdir-lock (flock unworkable on toybox; stale-recovery by PID)
  blobs/<sha256>       # cache of verified blobs (ORIGINAL content, already decompressed)
  rollback/<version>/<path>   # backup of overwritten files
  staged/<path>.vdlu-new      # REBOOT-hard awaiting swap at boot
  target.json          # PINNED manifest of the in-flight transaction (presence = active transaction; becomes current.json on DONE)
  plan.tsv  plan.del   # engine's internal plan (progress); the WebUI IGNORES it (reads only journal/config/current)
```
`cancelled:true` dans le journal = l'engine s'est arrete sur une annulation (un etat non terminal, reprenable ;
`error` reste null).

Engine vendorise dans le module : `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`). `$MODULE_DIR =
/data/adb/modules/<module>`. L'engine recoit via env : `VDLU_DIR`, `MODULE_DIR`, `MODID`.

## 2. CLI de l'engine (composant ENGINE)

`sh update.sh <cmd>` - rc 0 = ok, !=0 = erreur (stderr donne la raison) :

| cmd | fait |
|---|---|
| `check` | DIFF : telecharge le manifeste, compare ; imprime un JSON d'une ligne `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}` ; ne change rien. Appareil EN AVANCE sur le feed (downgrade bloque, durci) = un etat BENIN : `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (jamais "check failed"). rc de do_diff : 2 fetch/parse, 3 verify/meta, 4 ahead |
| `run` | cycle complet : DIFF→FETCH→APPLY→COMMIT ; respecte `cancel` ; ecrit la progression dans `journal.json` ; applique LIVE, met en scene REBOOT-hard |
| `resume` | reprend la transaction de `journal.json` depuis la phase courante (idempotent) |
| `boot` | mode pre-zygote : `resume` + fait le SWAP des `staged/*.vdlu-new` (applique le `.so`), ferme `PENDING_REBOOT`→`DONE` |
| `status` | imprime `journal.json` (ou `{"state":"idle"}`) |
| `cancel` | cree `$VDLU_DIR/cancel` (un `run` en cours s'arrete au prochain point sur) |

Source des blobs/manifeste : `source` de la config. `<source>` + `/manifest.json`, `/blobs/<sha>`, `/blobs/<sha>.gz`.
`source` commence par `https://` (curl statique recupere, TLS) ou `file://` (staging local).

## 3. manifest.json (produit par le PRODUCER, consomme par l'ENGINE)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":3, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = l'arbre cible COMPLET. `class` : `live` (webroot/bin/lib/confs/scripts-on-demand/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`, `system/**`, `*.rule`).
  Par defaut selon le path ; ne degrade jamais `reboot`→`live`.
- `enc` : `gz` (gzip `-9 -n`, deterministe ; toybox gunzip sur l'appareil) seulement quand ca compresse bien ET
  que la taille est significative ; `sha256` est TOUJOURS du contenu original.
- `sig` : signature du manifeste canonique SANS le champ `sig` (§4 de verify).

## 4. journal.json (l'ENGINE ecrit, la WEBUI lit - le contrat de progression)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

Machine a etats (ordre fixe) : `PLANNED→FETCHING→FETCHED→APPLYING→APPLIED_LIVE→(PENDING_REBOOT|DONE)`.
`DONE` seulement une fois qu'un re-hash de TOUT correspond. Un REBOOT-hard mis en scene ⇒ `PENDING_REBOOT` (pas
`DONE`). Sorties de la phase `fetch` : `ERROR` (echec dur) ou `DEFERRED` (net_policy a bloque le telechargement -
benin/reprenable, pas une erreur).

## 5. config (key=value, un par ligne ; editable dans la WEBUI)

```
auto_on_webui_open=0
auto_on_reboot=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=trusted        # trusted | hardened. CODE DEFAULT (line absent) = hardened (fail-closed, 9a9a824)
net_policy=any         # any (Wi-Fi+mobile) | wifi (Wi-Fi only) | mobile (mobile only) - gates the DOWNLOAD by network type
allow_metered=0        # ⚠️ SUPERSEDED by net_policy (not consumed by the engine)
pubkey_dir=keyring     # relative to $MODULE_DIR/vdlu (keyring of pubkeys for verify)
ca_path=               # empty = auto-detect of the Android trust store; set a path to override
tools_source=          # empty = derived from source (.../vdlu-tools); feed of the static curl
boot_retry_interval=30 # seconds between probes when BOOT finds the device offline (floor 5s)
boot_retry_minutes=0   # ceiling of the PATIENT retry (AWAKE-time) only at boot; 0 = off. Battery-safe (no wakelock,
                       # no held lock, route probe never wakes the radio) -> a generous ceiling is ~free
```

**Retry au boot (offline) - PATIENT, sans danger pour la batterie :** seulement au `boot` (jamais sur
check/auto-open). Si le fetch du manifeste echoue pour cause de RESEAU (`fetch_offline` classe selon l'exit du
fetcher), il attend et reessaie jusqu'au succes OU l'epuisement de `boot_retry_minutes` de temps AWAKE. Un design
qui **ne tient rien et ne draine pas** :
- **Zero wakelock :** entre les essais c'est `sleep`, qui se fige en deep-sleep → l'appareil dort normalement
  (~zero batterie) ; le retry se met en pause et reprend une fois que l'appareil est deja reveille.
- **Zero lock tenu :** `acquire_lock_try`+release ENTRE les essais (ne tient pas le lock pendant l'attente) →
  `run`/check manuel ne bloquent jamais ; si un run manuel met en scene un TARGET entre-temps, le boot s'efface.
- **Ne reveille pas la radio pour rien :** un sondage `net_allowed` (via `net_type`/`ip route get`, une recherche
  de route du noyau qui respecte le policy-routing d'Android ; pas de paquet) controle chaque essai - il ne
  depense un fetch qu'une fois le reseau apparu.
- Ne reessaie JAMAIS un echec deterministe (manifeste/sig/downgrade). `--connect-timeout 15` sur le fetch (ne se
  bloque pas sur un portail captif). `service.sh` le met en arriere-plan (le boot ne bloque jamais).
- ⛔ **DUR : activer `boot_retry_minutes>0` exige l'engine PATIENT** (celui avec
  `net_allowed`+`acquire_lock_try`, canonique `da7115f4`+). Le retry de boot PRECEDENT (tient le lock toute la
  fenetre + reessaie un curl aveugle offline) **DRAINE la batterie/reveille la radio** - activer le retry dans un
  vieil engine est un footgun. En l'activant, vendorise l'engine actuel.

**`net_policy` (any|wifi|mobile) :** controle le **TELECHARGEMENT** par type de reseau. `net_type()` classe la
sortie de `ip route get` (iface cellulaire `rmnet/ccmni/v4-*/clat` = mobile ; tout le reste = wifi ; recherche du
noyau, pas de paquet). `net_allowed()` compare contre `net_policy` et controle `do_fetch` (blobs) + le sondage du
retry de boot patient. Le **check du manifeste reste libre** (minuscule → l'UI signale une mise a jour sur
n'importe quel reseau) ; seul le telechargement attend le reseau autorise. Un telechargement sur un reseau non
autorise = l'etat **`DEFERRED`** dans le journal (PAS ERROR ; un toast INFO bleu doux "en attente du reseau X" ;
plan/target persistent, il reprend au prochain check/boot sur le bon reseau). `net_policy` **remplace**
`allow_metered` (qui n'a jamais ete consomme). Engine `97baf887`+ (`file://` n'est jamais controle).

## 6. Signature (le PRODUCER signe sur le PC via openssl ; l'ENGINE verifie sur l'appareil via ed25519-mini)

- Canonicalisation : le manifeste SANS `sig`, cles triees, JSON compact (sans espaces superflus), UTF-8.
  Ce qui est signe/verifie = le `sha256` hex de cette forme canonique (donne un determinisme inter-outils).
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` → injecte `key_id` + `sig` (base64 de la signature ed25519 du sha256 canonique) dans le manifeste, in place.
- `engine/vdlu-verify <manifest.json> <keyring_dir>` → rc 0 si la `sig` correspond a la pubkey `<key_id>.pub` du
  keyring (SLIM : pubkey **RAW 32 octets**). En interne, pas d'openssl : toybox `sha256sum`/`base64 -d` + le
  binaire `ed25519-mini` embarque (CLI `ed25519-mini <pub32> <msg> <sig64>`, rc 0=valide/1=invalide/2=usage).
  rc!=0 = rejet. **`profile=hardened` ⇒ verify obligatoire ; echec = abandon.**
  `profile=trusted` ⇒ verify est best-effort (source deja de confiance via SSH), mais le hash de chaque blob est TOUJOURS verifie.
- `producer/vdlu-keygen <id> <out>` → genere `<id>.pem` (priv) + `<id>.pub` (PEM, pour le tooling sur le PC) +
  `<id>.pub.raw` (**RAW 32B** = le `<id>.pub` du keyring slim sur l'appareil). openssl `genpkey -algorithm ed25519`.

## 7. Blob - verification (ENGINE)

Telecharge `<source>/blobs/<sha>` (ou `.gz` si `enc=gz`), ecrit `.part`, si `gz` decompresse (`gunzip`),
verifie `sha256sum` == le `sha256` du manifeste ; correspond → `mv` atomique vers `$VDLU_DIR/blobs/<sha>`. 3
echecs sur le meme blob = abandonne la phase (rien d'applique). Un blob deja dans `$VDLU_DIR/blobs/<sha>` avec un
hash ok = saute le telechargement.

## 8. APPLY par classe (ENGINE)

- `live`/`soft` : sauvegarde `rollback/<v>/<path>` → ecrit `$MODULE_DIR/<path>.vdlu-tmp` depuis le blob → `chmod mode` →
  `rename` atomique par-dessus la cible. Deja au hash cible = skip. (Dans la variante Zygisk l'ecriture va dans le
  repertoire monte = merge par fichier, jamais de `rm -rf` du repertoire.)
- `reboot` : materialise dans `$VDLU_DIR/staged/<path>.vdlu-new` (ne touche PAS le vivant). Le swap est au `boot`.
- `delete[]` : sauvegarde → suppression.

## 9. WEBUI ↔ ENGINE (composant WEBUI)

- Declenche : `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (en arriere-plan).
- Progression : un poll leger `ksu.exec("cat $VDLU_DIR/journal.json")` toutes les ~1s ; rend `{phase,state,total,done,current,bytes}`.
- Vivacite : journal absent pendant 8 ticks ⇒ "pas de reponse". Journal FIGE (memes valeurs) pendant 20 ticks ⇒ verifie `lock.d` : vivant = continue (fetch lent d'1 blob), mort = erreur + Resume. Sans cela, un run mort en plein fetch figerait le toast sur "mise a jour".
- Cancel : `ksu.exec("touch $VDLU_DIR/cancel")`.
- Config : lit/ecrit `$VDLU_DIR/config` (key=value) dans un onglet "Updates".
- Toast : barre + `phase done/total · current` ; a la fin avec `reboot_pending` ⇒ un bandeau persistant "redemarrer pour activer le .so".
- Auto-open (`auto_on_webui_open=1`) : fait d'abord un `check()` SILENCIEUX (sans toast de progression) ; ne declenche le `run`+toast persistant que si `update && fetch>0`. A jour/en avance/rien de neuf = un resultat inline dans le panneau, zero toast residuel. Non intrusif comme le bouton manuel (le toast n'apparait que quand il y a un vrai telechargement). Le bootstrap de curl est unique.

## 10. Integration dans la demo (composant INTEGRATION) - SNIPPETS, ne pas editer les fichiers vivants

Produit, dans `integration/demo/`, des snippets + un `INTEGRATION.md` disant ou va chacun (sans appliquer) :
- le hook `auto_on_reboot` dans `post-fs-data`/`service.sh` (pre-zygote → `update.sh boot`) et `auto_on_webui_open`.
- les defauts de `config` + le keyring embarque + la vendorisation (`modules/<mod>/vdlu/`).
- la variante PARTIELLE (merge dans le repertoire monte).

## 11. Toolchain recupere + baseline (SLIM, Approche B)

**Disposition dans le module (zip) :** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`. **PAS** de `bin/` (openssl/curl/zstd). `customize.sh` peut elaguer
`verify/` jusqu'a l'ABI de l'appareil (`vdlu-verify` trouve le mini a `<dir>/ed25519-mini` OU `<dir>/verify/<abi>/ed25519-mini`).

**ed25519-mini** (binaire embarque, verify seul) : `ed25519-mini <pubkey32> <msg> <sig64>` → rc 0=valide,
1=invalide, 2=usage/IO. msg = les octets signes exacts (ne re-hashe PAS). TweetNaCl PD, statique par ABI, PROVENANCE.

**tools-feed** (profil public/https seulement) : servi a `<tools_source>` (defaut derive : remplace le dernier
segment de `source` par `vdlu-tools`, p. ex. `https://<user>.github.io/<repo>/vdlu-tools`). Contient :
- `tools-manifest.json` - un manifeste `vdlu-pack` SIGNE sur l'arbre `<abi>/curl`, epinglant le `sha256` de
  chaque curl (meme cle `release-2026`).
- `<abi>/curl` - le curl **statique** RAW (autonome, ~1MB ; curl 8.11.1 + mbedTLS). 🪤 mbedTLS ne porte PAS de
  CA bundle : `fetch_url` passe `--capath` (auto-detection du trust store d'Android : `/system/etc/security/cacerts`
  → APEX conscrypt ; `ca_path` surcharge). Pas de capath = erreur 60. L'integrite est l'ed25519 ; le cert-check est defense en profondeur.

**install-tool** (ENGINE) : `update.sh install-tool <abi>` lit `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}`
(la WEBUI le telecharge via `fetch()` et l'ecrit la), **verifie la signature du tools-manifest (ed25519-mini,
OBLIGATOIRE dans tout profil)** + le hash du curl == manifeste, et seulement alors l'installe a `$VDLU_DIR/tools/<abi>/curl` (0755).
Le curl tourne en root → sig+hash avant exec ferme le RCE. Persiste en Tier-2 : jamais re-telecharge (sauf a la desinstallation).

**fetch-bootstrap** (WEBUI, `ensureToolchain()`) : tourne avant check/run/resume. `file://` = no-op ; curl DEJA
disponible (Tier-2, OU `module/bin/<abi>/curl` d'un module **auto-empaquete**, OU systeme) = no-op
(VDLU reutilise le curl existant) ; seul `https` **sans aucun curl** telecharge curl + tools-manifest via la webview, les
ecrit dans `.work` (base64 en morceaux via `ksu.exec`), appelle `install-tool`. Confiance = la verification sur l'appareil, pas le telechargement.

> 🪤 **Slim (fetch-bootstrap) ≠ obligatoire.** Un module dont le `bin/` existe pour SES PROPRES fonctions (p. ex.
> il empaquete restic/rclone/age/tar/curl...) **ne** s'allege **pas** a ~2MB ni ne telecharge curl - VDLU adopte
> l'engine slim (gz, mini, baseline, fixes) et **reutilise** le toolchain embarque. Seuls les modules sans leur
> propre toolchain gagnent les ~2MB.

**baseline.json** (fix from:0) : la release copie le `manifest.json` SIGNE de la version livree vers
`vdlu/baseline.json` ; a une installation fraiche l'engine seme `current.json` a partir de lui (`init_paths`,
seulement si absent) → l'appareil nait "a jour", sans auto-mise-a-jour de lui-meme et sans re-fetch.

<!-- doc-footer -->

---

> _Cette documentation a été générée avec Claude (Anthropic) et est maintenue par VD171. Les corrections et améliorations sont les bienvenues ; voir [CONTRIBUTING.md](CONTRIBUTING.md)._
