> **Languages:** [English](../INTERFACES.md) · [العربية](../ar/INTERFACES.md) · [Čeština](../cs/INTERFACES.md) · [Deutsch](../de/INTERFACES.md) · [Español](../es/INTERFACES.md) · [فارسی](../fa/INTERFACES.md) · Français · [हिन्दी](../hi/INTERFACES.md) · [Bahasa Indonesia](../id/INTERFACES.md) · [Italiano](../it/INTERFACES.md) · [日本語](../ja/INTERFACES.md) · [한국어](../ko/INTERFACES.md) · [Nederlands](../nl/INTERFACES.md) · [Polski](../pl/INTERFACES.md) · [Português](../pt/INTERFACES.md) · [Русский](../ru/INTERFACES.md) · [Svenska](../sv/INTERFACES.md) · [ไทย](../th/INTERFACES.md) · [Türkçe](../tr/INTERFACES.md) · [Українська](../uk/INTERFACES.md) · [Tiếng Việt](../vi/INTERFACES.md) · [中文](../zh/INTERFACES.md)

---

# VDLU - Contrat d'interface (la couture entre les composants)

**Loi de convergence :** chaque composant se conforme à ce fichier. Les pièces issues de 4 agents doivent
**s'emboîter** - les signatures CLI, les noms de fichier et les clés JSON ci-dessous sont **immuables** (un
changement implique de s'aligner ici d'abord).

Principes hérités des repos : **sh POSIX pur** sur l'appareil (pas de bashismes ; tourne avec toybox/busybox +
`sha256sum`/`gzip`/`base64` de toybox + le `curl` récupéré + le `ed25519-mini` embarqué - mince, sans bundle de
binaires), **zéro commentaire gratuit**, **toujours release**, **rigueur face à l'échec** (transaction
reprenable, rien de faussement "terminé", rien de perdu), **rien de relâché**.

---

## 1. Disposition de l'état (Tier-2, hors du répertoire du module)

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
`cancelled:true` dans le journal = l'engine s'est arrêté sur une annulation (un état non terminal, reprenable ;
`error` reste null).

Engine vendorisé dans le module : `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`). `$MODULE_DIR =
/data/adb/modules/<module>`. L'engine reçoit via env : `VDLU_DIR`, `MODULE_DIR`, `MODID`.

## 2. CLI de l'engine (composant ENGINE)

`sh update.sh <cmd>` - rc 0 = ok, !=0 = erreur (stderr donne la raison) :

| cmd | fait |
|---|---|
| `check` | DIFF : télécharge le manifeste, compare ; imprime un JSON d'une ligne `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}` ; ne change rien. Appareil EN AVANCE sur le feed (downgrade bloqué, durci) = un état BÉNIN : `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (jamais "check failed"). rc de do_diff : 2 fetch/parse, 3 verify/meta, 4 ahead |
| `run` | cycle complet : DIFF→FETCH→APPLY→COMMIT ; respecte `cancel` ; écrit la progression dans `journal.json` ; applique LIVE, met en scène REBOOT-hard |
| `resume` | reprend la transaction de `journal.json` depuis la phase courante (idempotent) |
| `boot` | mode pré-zygote : `resume` + fait le SWAP des `staged/*.vdlu-new` (applique le `.so`), ferme `PENDING_REBOOT`→`DONE` |
| `status` | imprime `journal.json` (ou `{"state":"idle"}`) |
| `cancel` | crée `$VDLU_DIR/cancel` (un `run` en cours s'arrête au prochain point sûr) |

Source des blobs/manifeste : `source` de la config. `<source>` + `/manifest.json`, `/blobs/<sha>`, `/blobs/<sha>.gz`.
`source` commence par `https://` (curl statique récupéré, TLS) ou `file://` (staging local).

## 3. manifest.json (produit par le PRODUCER, consommé par l'ENGINE)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":3, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = l'arbre cible COMPLET. `class` : `live` (webroot/bin/lib/confs/scripts-on-demand/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`, `system/**`, `*.rule`).
  Par défaut selon le path ; ne dégrade jamais `reboot`→`live`.
- `enc` : `gz` (gzip `-9 -n`, déterministe ; toybox gunzip sur l'appareil) seulement quand ça compresse bien ET
  que la taille est significative ; `sha256` est TOUJOURS du contenu original.
- `sig` : signature du manifeste canonique SANS le champ `sig` (§4 de verify).

## 4. journal.json (l'ENGINE écrit, la WEBUI lit - le contrat de progression)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

Machine à états (ordre fixe) : `PLANNED→FETCHING→FETCHED→APPLYING→APPLIED_LIVE→(PENDING_REBOOT|DONE)`.
`DONE` seulement une fois qu'un re-hash de TOUT correspond. Un REBOOT-hard mis en scène ⇒ `PENDING_REBOOT` (pas
`DONE`). Sorties de la phase `fetch` : `ERROR` (échec dur) ou `DEFERRED` (net_policy a bloqué le téléchargement -
bénin/reprenable, pas une erreur).

## 5. config (key=value, un par ligne ; éditable dans la WEBUI)

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
check/auto-open). Si le fetch du manifeste échoue pour cause de RÉSEAU (`fetch_offline` classe selon l'exit du
fetcher), il attend et réessaie jusqu'au succès OU l'épuisement de `boot_retry_minutes` de temps AWAKE. Un design
qui **ne tient rien et ne draine pas** :
- **Zéro wakelock :** entre les essais c'est `sleep`, qui se fige en deep-sleep → l'appareil dort normalement
  (~zéro batterie) ; le retry se met en pause et reprend une fois que l'appareil est déjà réveillé.
- **Zéro lock tenu :** `acquire_lock_try`+release ENTRE les essais (ne tient pas le lock pendant l'attente) →
  `run`/check manuel ne bloquent jamais ; si un run manuel met en scène un TARGET entre-temps, le boot s'efface.
- **Ne réveille pas la radio pour rien :** un sondage `net_allowed` (via `net_type`/`ip route get`, une recherche
  de route du noyau qui respecte le policy-routing d'Android ; pas de paquet) contrôle chaque essai - il ne
  dépense un fetch qu'une fois le réseau apparu.
- Ne réessaie JAMAIS un échec déterministe (manifeste/sig/downgrade). `--connect-timeout 15` sur le fetch (ne se
  bloque pas sur un portail captif). `service.sh` le met en arrière-plan (le boot ne bloque jamais).
- ⛔ **DUR : activer `boot_retry_minutes>0` exige l'engine PATIENT** (celui avec
  `net_allowed`+`acquire_lock_try`, canonique `da7115f4`+). Le retry de boot PRÉCÉDENT (tient le lock toute la
  fenêtre + réessaie un curl aveugle offline) **DRAINE la batterie/réveille la radio** - activer le retry dans un
  vieil engine est un footgun. En l'activant, vendorise l'engine actuel.

**`net_policy` (any|wifi|mobile) :** contrôle le **TÉLÉCHARGEMENT** par type de réseau. `net_type()` classe la
sortie de `ip route get` (iface cellulaire `rmnet/ccmni/v4-*/clat` = mobile ; tout le reste = wifi ; recherche du
noyau, pas de paquet). `net_allowed()` compare contre `net_policy` et contrôle `do_fetch` (blobs) + le sondage du
retry de boot patient. Le **check du manifeste reste libre** (minuscule → l'UI signale une mise à jour sur
n'importe quel réseau) ; seul le téléchargement attend le réseau autorisé. Un téléchargement sur un réseau non
autorisé = l'état **`DEFERRED`** dans le journal (PAS ERROR ; un toast INFO bleu doux "en attente du réseau X" ;
plan/target persistent, il reprend au prochain check/boot sur le bon réseau). `net_policy` **remplace**
`allow_metered` (qui n'a jamais été consommé). Engine `97baf887`+ (`file://` n'est jamais contrôlé).

## 6. Signature (le PRODUCER signe sur le PC via openssl ; l'ENGINE vérifie sur l'appareil via ed25519-mini)

- Canonicalisation : le manifeste SANS `sig`, clés triées, JSON compact (sans espaces superflus), UTF-8.
  Ce qui est signé/vérifié = le `sha256` hex de cette forme canonique (donne un déterminisme inter-outils).
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` → injecte `key_id` + `sig` (base64 de la signature ed25519 du sha256 canonique) dans le manifeste, in place.
- `engine/vdlu-verify <manifest.json> <keyring_dir>` → rc 0 si la `sig` correspond à la pubkey `<key_id>.pub` du
  keyring (SLIM : pubkey **RAW 32 octets**). En interne, pas d'openssl : toybox `sha256sum`/`base64 -d` + le
  binaire `ed25519-mini` embarqué (CLI `ed25519-mini <pub32> <msg> <sig64>`, rc 0=valide/1=invalide/2=usage).
  rc!=0 = rejet. **`profile=hardened` ⇒ verify obligatoire ; échec = abandon.**
  `profile=trusted` ⇒ verify est best-effort (source déjà de confiance via SSH), mais le hash de chaque blob est TOUJOURS vérifié.
- `producer/vdlu-keygen <id> <out>` → génère `<id>.pem` (priv) + `<id>.pub` (PEM, pour le tooling sur le PC) +
  `<id>.pub.raw` (**RAW 32B** = le `<id>.pub` du keyring slim sur l'appareil). openssl `genpkey -algorithm ed25519`.

## 7. Blob - vérification (ENGINE)

Télécharge `<source>/blobs/<sha>` (ou `.gz` si `enc=gz`), écrit `.part`, si `gz` décompresse (`gunzip`),
vérifie `sha256sum` == le `sha256` du manifeste ; correspond → `mv` atomique vers `$VDLU_DIR/blobs/<sha>`. 3
échecs sur le même blob = abandonne la phase (rien d'appliqué). Un blob déjà dans `$VDLU_DIR/blobs/<sha>` avec un
hash ok = saute le téléchargement.

## 8. APPLY par classe (ENGINE)

- `live`/`soft` : sauvegarde `rollback/<v>/<path>` → écrit `$MODULE_DIR/<path>.vdlu-tmp` depuis le blob → `chmod mode` →
  `rename` atomique par-dessus la cible. Déjà au hash cible = skip. (Dans la variante Zygisk l'écriture va dans le
  répertoire monté = merge par fichier, jamais de `rm -rf` du répertoire.)
- `reboot` : matérialise dans `$VDLU_DIR/staged/<path>.vdlu-new` (ne touche PAS le vivant). Le swap est au `boot`.
- `delete[]` : sauvegarde → suppression.

## 9. WEBUI ↔ ENGINE (composant WEBUI)

- Déclenche : `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (en arrière-plan).
- Progression : un poll léger `ksu.exec("cat $VDLU_DIR/journal.json")` toutes les ~1s ; rend `{phase,state,total,done,current,bytes}`.
- Vivacité : journal absent pendant 8 ticks ⇒ "pas de réponse". Journal FIGÉ (mêmes valeurs) pendant 20 ticks ⇒ vérifie `lock.d` : vivant = continue (fetch lent d'1 blob), mort = erreur + Resume. Sans cela, un run mort en plein fetch figerait le toast sur "mise à jour".
- Cancel : `ksu.exec("touch $VDLU_DIR/cancel")`.
- Config : lit/écrit `$VDLU_DIR/config` (key=value) dans un onglet "Updates".
- Toast : barre + `phase done/total · current` ; à la fin avec `reboot_pending` ⇒ un bandeau persistant "redémarrer pour activer le .so".
- Auto-open (`auto_on_webui_open=1`) : fait d'abord un `check()` SILENCIEUX (sans toast de progression) ; ne déclenche le `run`+toast persistant que si `update && fetch>0`. À jour/en avance/rien de neuf = un résultat inline dans le panneau, zéro toast résiduel. Non intrusif comme le bouton manuel (le toast n'apparaît que quand il y a un vrai téléchargement). Le bootstrap de curl est unique.

## 10. Intégration dans la démo (composant INTEGRATION) - SNIPPETS, ne pas éditer les fichiers vivants

Produit, dans `integration/demo/`, des snippets + un `INTEGRATION.md` disant où va chacun (sans appliquer) :
- le hook `auto_on_reboot` dans `post-fs-data`/`service.sh` (pré-zygote → `update.sh boot`) et `auto_on_webui_open`.
- les défauts de `config` + le keyring embarqué + la vendorisation (`modules/<mod>/vdlu/`).
- la variante PARTIELLE (merge dans le répertoire monté).

## 11. Toolchain récupéré + baseline (SLIM, Approche B)

**Disposition dans le module (zip) :** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`. **PAS** de `bin/` (openssl/curl/zstd). `customize.sh` peut élaguer
`verify/` jusqu'à l'ABI de l'appareil (`vdlu-verify` trouve le mini à `<dir>/ed25519-mini` OU `<dir>/verify/<abi>/ed25519-mini`).

**ed25519-mini** (binaire embarqué, verify seul) : `ed25519-mini <pubkey32> <msg> <sig64>` → rc 0=valide,
1=invalide, 2=usage/IO. msg = les octets signés exacts (ne re-hashe PAS). TweetNaCl PD, statique par ABI, PROVENANCE.

**tools-feed** (profil public/https seulement) : servi à `<tools_source>` (défaut dérivé : remplace le dernier
segment de `source` par `vdlu-tools`, p. ex. `https://<user>.github.io/<repo>/vdlu-tools`). Contient :
- `tools-manifest.json` - un manifeste `vdlu-pack` SIGNÉ sur l'arbre `<abi>/curl`, épinglant le `sha256` de
  chaque curl (même clé `release-2026`).
- `<abi>/curl` - le curl **statique** RAW (autonome, ~1MB ; curl 8.11.1 + mbedTLS). 🪤 mbedTLS ne porte PAS de
  CA bundle : `fetch_url` passe `--capath` (auto-détection du trust store d'Android : `/system/etc/security/cacerts`
  → APEX conscrypt ; `ca_path` surcharge). Pas de capath = erreur 60. L'intégrité est l'ed25519 ; le cert-check est défense en profondeur.

**install-tool** (ENGINE) : `update.sh install-tool <abi>` lit `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}`
(la WEBUI le télécharge via `fetch()` et l'écrit là), **vérifie la signature du tools-manifest (ed25519-mini,
OBLIGATOIRE dans tout profil)** + le hash du curl == manifeste, et seulement alors l'installe à `$VDLU_DIR/tools/<abi>/curl` (0755).
Le curl tourne en root → sig+hash avant exec ferme le RCE. Persiste en Tier-2 : jamais re-téléchargé (sauf à la désinstallation).

**fetch-bootstrap** (WEBUI, `ensureToolchain()`) : tourne avant check/run/resume. `file://` = no-op ; curl DÉJÀ
disponible (Tier-2, OU `module/bin/<abi>/curl` d'un module **auto-empaqueté**, OU système) = no-op
(VDLU réutilise le curl existant) ; seul `https` **sans aucun curl** télécharge curl + tools-manifest via la webview, les
écrit dans `.work` (base64 en morceaux via `ksu.exec`), appelle `install-tool`. Confiance = la vérification sur l'appareil, pas le téléchargement.

> 🪤 **Slim (fetch-bootstrap) ≠ obligatoire.** Un module dont le `bin/` existe pour SES PROPRES fonctions (p. ex.
> il empaquète restic/rclone/age/tar/curl...) **ne** s'allège **pas** à ~2MB ni ne télécharge curl - VDLU adopte
> l'engine slim (gz, mini, baseline, fixes) et **réutilise** le toolchain embarqué. Seuls les modules sans leur
> propre toolchain gagnent les ~2MB.

**baseline.json** (fix from:0) : la release copie le `manifest.json` SIGNÉ de la version livrée vers
`vdlu/baseline.json` ; à une installation fraîche l'engine sème `current.json` à partir de lui (`init_paths`,
seulement si absent) → l'appareil naît "à jour", sans auto-mise-à-jour de lui-même et sans re-fetch.

<!-- doc-footer -->

---

> _Cette documentation a été générée avec Claude (Anthropic) et est maintenue par VD171. Les corrections et améliorations sont les bienvenues ; voir [CONTRIBUTING.md](CONTRIBUTING.md)._
