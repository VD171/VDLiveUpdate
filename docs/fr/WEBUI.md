> **Languages:** [English](../WEBUI.md) · [العربية](../ar/WEBUI.md) · [Čeština](../cs/WEBUI.md) · [Deutsch](../de/WEBUI.md) · [Español](../es/WEBUI.md) · [فارسی](../fa/WEBUI.md) · Français · [हिन्दी](../hi/WEBUI.md) · [Bahasa Indonesia](../id/WEBUI.md) · [Italiano](../it/WEBUI.md) · [日本語](../ja/WEBUI.md) · [한국어](../ko/WEBUI.md) · [Nederlands](../nl/WEBUI.md) · [Polski](../pl/WEBUI.md) · [Português](../pt/WEBUI.md) · [Русский](../ru/WEBUI.md) · [Svenska](../sv/WEBUI.md) · [ไทย](../th/WEBUI.md) · [Türkçe](../tr/WEBUI.md) · [Українська](../uk/WEBUI.md) · [Tiếng Việt](../vi/WEBUI.md) · [中文](../zh/WEBUI.md)

---

# VDLU - Widget WebUI (mise a jour flashless)

L'interface VDLU (VD Live Update) pour une WebUI de root manager KernelSU/APatch. Vanilla JS, pas de framework,
pas de build, pas de CDN. Drop-in : l'`index.html` hote charge les 2 fichiers et appelle l'API.

Convergence : `INTERFACES.md` §9 (WEBUI↔ENGINE), §4 (journal.json), §5 (config).

## Fichiers

| Fichier | Quoi |
|---|---|
| `vdlu.js` | le composant - expose `window.VDLU` |
| `vdlu.css` | toast de progression, bandeau de reboot, onglet "Updates" (theme sombre, herite des variables de l'hote) |
| `demo.html` | page standalone avec un `ksu.exec` mocke - s'ouvre dans un navigateur, sans appareil |

## Integration dans l'`index.html` hote

```html
<link rel="stylesheet" href="vdlu.css">
...
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,   // $MODULE_DIR
    vdluDir:   '/data/adb/' + MODID + '/vdlu',  // $VDLU_DIR  (Tier-2, outside the module dir)
    modid:     MODID,
    module:    'Demo',                     // name shown in the toast (default: modid)
    exec:   ex,          // (optional) the host's ksu.exec wrapper; see below
    toast:  toast,       // (optional) the host's transient toast
    confirm: askConfirm  // (optional) the host's confirmation modal
  });

  VDLU.onWebUIOpen();                          // on load: evaluates journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // when the "Updates" tab is opened
</script>
```

### Ce que l'hote doit definir

- **`moduleDir`** = `$MODULE_DIR` (`/data/adb/modules/<modid>`), ou l'engine est vendorise
  (`vdlu/update.sh`).
- **`vdluDir`** = `$VDLU_DIR` (`/data/adb/<modid>/vdlu`), l'etat Tier-2 (`journal.json`, `config`,
  `cancel`).
- **`modid`** = l'id du module.

Le widget assemble la commande de l'engine portant deja l'env du contrat (§1) :
`VDLU_DIR=… MODULE_DIR=… MODID=… sh $MODULE_DIR/vdlu/update.sh <cmd>`. `run`/`resume` vont en
**arriere-plan** (`(… &)`), et la progression est lue par un poll leger (~1s) de `cat $VDLU_DIR/journal.json`.

### `exec`/`toast`/`confirm` (optionnels)

Si omis, le widget utilise les siens :
- **`exec(cmd)`** doit retourner une `Promise` qui **resout** avec stdout (rc 0) et **rejette** avec stderr
  (rc≠0) - exactement la signature du `ex()` du `webroot/index.html` de la Demo. Le fallback interne appelle
  `ksu.exec(cmd, '{}', cb)` avec le meme contrat.
- **`toast(msg)`** = une notification transitoire courte (le fallback injecte son propre mini-toast).
- **`confirm(title,msg,ok,danger,fn)`** = un modal (aujourd'hui utilise seulement par l'hote ; le widget n'exige
  aucune confirmation dans aucun flux).

Passer ceux de l'hote fait parler le widget a travers la MEME file serialisee et les memes visuels que le reste
de la WebUI.

## API publique (`window.VDLU`)

| Fonction | Fait |
|---|---|
| `init(opts)` | configure (voir ci-dessus). Retourne `window.VDLU`. |
| `onWebUIOpen()` | appelle-la au chargement : montre le bandeau si `reboot_pending` ; offre **Resume** s'il y a une transaction non terminale ; avec `auto_on_webui_open=1` elle lance une **auto-mise-a-jour SILENCIEUSE** (un `check()` silencieux d'abord ; ne declenche `run`+toast persistant que si `update && fetch>0` - a jour/en avance = resultat inline dans le panneau, zero toast). |
| `mountUpdatesPanel(el)` | rend l'onglet "Updates" dans `el` (id string ou element) : **Check for update**, **Update now**, les toggles `auto_on_webui_open`/`auto_on_reboot`, les champs de boot-retry, le select **Network** (`net_policy` : Wi-Fi+mobile / Wi-Fi seul / mobile seul) et les champs `source`/`channel`/`profile`. |
| `check()` | lance `update.sh check` ; `Promise<{update,from,to,fetch,reboot}>`. |
| `startUpdate()` | declenche `run` en arriere-plan + un toast de progression avec **Cancel**. |
| `cancel()` | cree `$VDLU_DIR/cancel` (l'engine s'arrete au point sur). |
| `resume()` | `update.sh resume` + toast (reprend la phase courante). |
| `refreshBanner()` | re-evalue le bandeau persistant de pending-reboot. |

Le toast (overlay de coin, non bloquant) et le bandeau (en haut, persistant) sont injectes par le widget dans
`document.body` - l'hote n'a besoin d'aucun HTML pour eux. L'onglet "Updates" est le seul point que l'hote alloue
(un `<div>` vide).

### Le flux d'etats que le toast reflete (journal.json, §4)

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)` ; `ERROR` a tout moment. Le
toast montre **une barre + `phase done/total · current · bytes`**. Terminaux :
- **`DONE`** → toast vert "v&lt;target&gt; applied".
- **`PENDING_REBOOT`** (ou `reboot_pending=true`) → toast vert + **bandeau persistant** "⚠️ Reboot to
  activate the new `.so` (vX)".
- **`ERROR`** → toast rouge avec la raison (`journal.error`/stderr). Ne feint jamais le succes.
- **Annule** → "cancelled - N/M, resumable" + un bouton **Resume**.

## Lancer la demo

Ouvre `demo.html` dans un navigateur (`xdg-open webui/demo.html`). Le `ksu.exec` mocke simule `update.sh` et le
`journal.json` qui evolue ; les boutons alternent entre les scenarios **LIVE→DONE**, **reboot_pending**, **erreur
en cours** et **annulable**. C'est le meme `vdlu.js`/`vdlu.css` que sur l'appareil.

## i18n (langue)

Les chaines du widget sont par defaut en **anglais** (neutre pour les modules publics multilingues). L'hote
surcharge n'importe quelle cle en passant un map dans `init` :

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- Un merge **partiel** convient : une cle manquante retombe sur le defaut anglais.
- Les cles de phase/state sont `ph_<phase>` / `st_<STATE>` ; le reste est plat (`cancel`, `updateNow`, …).
- Le map complet des cles = l'objet `DEFAULT_I18N` dans `vdlu.js` (aussi expose comme `VDLU.i18n`).
- Une traduction prete est fournie comme exemple travaille : `i18n/pt-BR.js`. Nouvelles langues = un fichier
  `i18n/<lang>.js` dans le meme moule, ou l'hote construit le map depuis son propre systeme i18n.

## Source unique (parite entre modules)

Ces `vdlu.js`/`vdlu.css` sont la **copie canonique**. Chaque module qui embarque le widget
**re-vendorise** cette copie octet pour octet dans son `webroot/` - il n'edite **jamais**
la sienne in place. Une nouvelle fonction du widget nait ici et descend par re-vendor ; l'inverse produit un
drift silencieux (c'est arrive en pratique : une copie vendorisee a pris du retard et il lui manquait
`net_policy`, le toast `DEFERRED` et les champs `boot_retry`).

Gardien : [`../tools/webui-parity.sh`](../../tools/webui-parity.sh) trouve chaque copie dans l'arbre source et accuse
celles qui divergent de la canonique (seulement `vdlu.js`/`vdlu.css` ; le keyring est "verifier, pas copier").

```sh
tools/webui-parity.sh         # report; exits 1 if there is drift
tools/webui-parity.sh --fix   # re-vendors the divergent ones from the canonical
```

> 🪤 Le keyring (`keyring/<id>.pub` RAW 32B) et l'engine (`vdlu/update.sh`) ont leur propre cadence de
> re-vendor ; ce gardien couvre **seulement le widget WebUI**.

<!-- doc-footer -->

---

> _Cette documentation a été générée avec Claude (Anthropic) et est maintenue par VD171. Les corrections et améliorations sont les bienvenues ; voir [CONTRIBUTING.md](CONTRIBUTING.md)._
