# WebUI

VDLU fournit un widget WebUI optionnel prêt à insérer : un petit panneau "Updates" pour une WebUI de gestionnaire root KernelSU ou APatch. Il donne à l'utilisateur un bouton Check, un bouton Update now, un toast de progression en direct avec annulation, une bannière de redémarrage et un panneau de paramètres, le tout sans que l'utilisateur ne touche jamais un terminal.

C'est du **JavaScript vanilla** : pas de framework, pas d'étape de build, pas de CDN. Trois fichiers :

| Fichier | Ce que c'est |
|---|---|
| `vdlu.js` | le widget ; expose `window.VDLU` |
| `vdlu.css` | les styles pour le toast, la bannière et le panneau (thème sombre, hérite des variables CSS de l'hôte) |
| `demo.html` | une page autonome qui simule le pont de l'appareil, de sorte que toute l'UI tourne dans un navigateur ordinaire |

Le widget est entièrement optionnel. Le [[Engine]] tourne très bien seul depuis les déclencheurs de démarrage ; la WebUI n'est qu'un visage convivial par-dessus. Voir [[Quick Start]] pour le brancher dans un module.

---

## Comment l'UI parle au moteur : le pont `ksu.exec`

Le widget ne fait jamais rien de privilégié lui-même. Il construit une commande shell et la transmet au pont `ksu.exec` du gestionnaire root, qui l'exécute en tant que root et renvoie stdout / stderr / code de sortie. Tout ce que le panneau affiche est relu depuis des fichiers que le moteur écrit.

Le widget enveloppe ce pont dans une unique fonction `exec(cmd)` qui renvoie une `Promise` :

- **se résout** avec stdout quand la commande sort avec 0
- **se rejette** avec stderr (ou `rc=N`) sinon

Chaque commande porte l'environnement du contrat, assemblé par le widget :

```
VDLU_DIR=... MODULE_DIR=... MODID=... sh $MODULE_DIR/vdlu/update.sh <cmd>
```

Quelques appels concrets :

- **Démarrer une mise à jour :** `update.sh run` est lancé en **arrière-plan** (`(... &)`) afin que l'UI ne soit jamais bloquée par un long téléchargement.
- **Lire la progression :** un sondage léger (environ une fois par seconde) de `cat $VDLU_DIR/journal.json`.
- **Annuler :** `touch $VDLU_DIR/cancel` (le moteur s'arrête au prochain point sûr).
- **Config :** lire et écrire `$VDLU_DIR/config` (clé=valeur), en préservant l'ordre et les clés inconnues et en ne touchant que les clés que l'utilisateur a modifiées.

Si l'hôte transmet ses propres auxiliaires `exec`, `toast` et `confirm` à `init()`, le widget passe par la file de commandes sérialisée et les visuels propres à l'hôte, de sorte qu'il a l'apparence et le comportement du reste de cette WebUI. S'ils sont omis, le widget se rabat sur un appel direct à `ksu.exec` et injecte son propre mini-toast.

---

## Le toast de progression (avec annulation)

Une fois qu'une mise à jour est en cours, le widget affiche un toast non bloquant dans un coin et sonde `journal.json`. Le toast reflète la machine à états du moteur :

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

Il rend une barre de progression plus une ligne `phase done/total - current file - bytes`, et porte un bouton **Cancel** tout du long. Les états terminaux reçoivent chacun leur propre traitement :

- **DONE** -> un toast vert, "vX applied - all verified".
- **PENDING_REBOOT** -> un toast vert plus une bannière de redémarrage persistante (ci-dessous).
- **ERROR** -> un toast rouge avec la raison issue de `journal.error` ou stderr, proposant Retry. Il ne simule jamais un succès.
- **Cancelled** -> un toast ambre, "cancelled - N/M applied, resumable", proposant **Resume**.
- **DEFERRED** -> un toast d'information bleu doux, "download deferred, waiting for the allowed network". C'est une attente bénigne de politique réseau, pas une erreur ; elle reprend au prochain check ou démarrage sur le bon réseau.

Le sondage est défensif. Un journal à moitié écrit (le moteur écrit de manière concurrente) est ignoré pour ce tick plutôt que mal analysé. Si le journal disparaît après qu'une progression a été vue, cela signifie que le commit l'a effacé : le widget rapporte DONE. Si le journal est absent dès le départ pendant 8 ticks, il rapporte "no response". Et si le journal se fige sur les mêmes valeurs pendant 20 ticks, le widget vérifie le `lock.d` du moteur : si le verrou est vivant c'est juste un fetch lent d'un unique blob et le toast continue d'attendre ; si le verrou est mort l'exécution est morte à mi-chemin, aussi le widget fait remonter une erreur avec un bouton Resume au lieu de tourner sur "updating" indéfiniment.

---

## La bannière de redémarrage

Certains fichiers ne peuvent pas être échangés sur un système en direct : un `.so`, un overlay `/system`, un `sepolicy.rule`. Le moteur échelonne ceux-là et marque la transaction `PENDING_REBOOT`. Le widget affiche alors une **bannière supérieure persistante** : "Reboot to activate the new `.so` (vX)". Elle reste jusqu'à ce que les fichiers échelonnés soient échangés au prochain démarrage. À l'ouverture de la WebUI la bannière est réévaluée depuis le journal, de sorte qu'un utilisateur qui ferme et rouvre l'UI la voit encore. Voir [[Reboot Handling]] pour ce qui se passe au démarrage.

Notez que la bannière se déclenche sur l'état terminal `PENDING_REBOOT`, pas sur le drapeau `reboot_pending` (qui passe à true dès qu'un `.so` entre dans le plan). Cela empêche la bannière d'apparaître en cours d'exécution avant que quoi que ce soit ne soit réellement échelonné.

---

## Le panneau "Updates" : bascules indépendantes par catégorie

`mountUpdatesPanel(el)` rend le panneau de paramètres dans un `<div>` vide fourni par l'hôte. Il comporte trois sections, et chaque contrôle est indépendant et s'enregistre de lui-même :

**Actions**
- **Check for updates** -> exécute `check`, affiche le résultat en ligne (à jour / plus récent que le feed / mise à jour disponible avec le nombre de fichiers et une étiquette de redémarrage).
- **Update now** -> déclenche `run` plus le toast de progression.

**Automation** (bascules indépendantes, chacune écrite dans `config` au moment où elle est basculée)
- **On WebUI open** (`auto_on_webui_open`) -> exécuter une mise à jour silencieuse à l'ouverture de l'UI.
- **On reboot** (`auto_on_reboot`) -> appliquer en pré-zygote au démarrage.
- **Boot retry every (s)** et **Boot retry up to (min)** -> champs numériques pour réessayer un fetch de manifeste lorsque l'appareil démarre hors ligne.

**Source**
- `source` (l'URL du feed), `channel` (stable / canary), `profile` (trusted / hardened), et un sélecteur **Network** correspondant à `net_policy` (Wi-Fi + mobile / Wi-Fi seul / mobile seul).

Les bascules et les champs numériques s'enregistrent immédiatement et reviennent visuellement en arrière si l'écriture échoue. Les champs texte et sélection de la section Source se marquent comme modifiés et s'enregistrent ensemble via un bouton Save explicite. Le panneau ne réécrit que les clés que l'utilisateur a touchées, de sorte que toute clé de config inconnue ou future est préservée.

### Comportement d'ouverture automatique

`onWebUIOpen()` est appelé au chargement de l'hôte. Il évalue le journal (affichant la bannière de redémarrage ou proposant Resume pour une transaction non terminale laissée par une session précédente), puis, si `auto_on_webui_open=1`, il exécute d'abord un `check()` **silencieux**. Le toast de progression persistant et le `run` réel ne se déclenchent que lorsqu'il y a un vrai téléchargement à faire (`update && fetch > 0`). Si l'appareil est à jour ou en avance sur le feed, le résultat s'affiche en ligne dans le panneau et aucun toast ne reste à l'écran, de sorte que la mise à jour automatique est aussi peu intrusive que le bouton manuel.

---

## i18n (chaînes par langue)

Chaque chaîne de l'UI est par défaut en **anglais**, qui est le choix neutre pour les modules publics multilingues. La carte complète des clés vit dans l'objet `DEFAULT_I18N` dans `vdlu.js` (également exposée comme `VDLU.i18n`). Un hôte surcharge n'importe quel sous-ensemble de clés en passant une carte à `init({ i18n: ... })` :

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>
  VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x',
              i18n: window.VDLU_I18N_PT_BR });
</script>
```

- Une carte **partielle** convient : toute clé manquante se rabat sur la valeur anglaise par défaut.
- Les étiquettes de phase et d'état utilisent les clés `ph_<phase>` et `st_<STATE>` ; le reste sont des clés plates comme `cancel`, `updateNow`.
- Une traduction détaillée (`i18n/pt-BR.js`) est livrée comme modèle ; une nouvelle langue n'est qu'un fichier `i18n/<lang>.js` de la même forme, ou l'hôte construit la carte depuis son propre système i18n.

---

## demo.html : exécuter l'UI sans appareil

`demo.html` simule le pont `ksu.exec` afin que exactement les mêmes `vdlu.js` et `vdlu.css` tournent dans un navigateur ordinaire, sans root et sans téléphone :

```sh
xdg-open webui/demo.html
```

Le simulacre imite `update.sh` et un `journal.json` évolutif, et ses boutons basculent entre les scénarios : une mise à jour en direct jusqu'à DONE, une fin `reboot_pending`, une erreur à mi-chemin et une exécution annulable. C'est la façon la plus rapide de voir et d'itérer sur l'UI, et c'est ce que vous vérifiez avant d'intégrer le widget dans un module.

---

## Le brancher dans un module (le déclencheur d'ouverture de WebUI)

L'`index.html` de l'hôte charge les deux fichiers et appelle trois fonctions :

```html
<link rel="stylesheet" href="vdlu.css">
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,   // $MODULE_DIR (where the engine is vendored)
    vdluDir:   '/data/adb/' + MODID + '/vdlu',  // $VDLU_DIR  (Tier-2 state, outside the module dir)
    modid:     MODID,
    module:    'Demo',        // friendly name shown in the toast (default: modid)
    exec:   ex,               // optional: the host's ksu.exec wrapper
    toast:  toast,            // optional: the host's transient toast
    confirm: askConfirm       // optional: the host's modal
  });

  VDLU.onWebUIOpen();                          // the WebUI-open trigger: banner + auto-update eval
  VDLU.mountUpdatesPanel('b-updates');         // render the "Updates" tab into an empty div
</script>
```

L'hôte n'a qu'à fournir les chemins Tier-2 et allouer un `<div>` vide pour le panneau ; le toast et la bannière sont injectés dans `document.body` par le widget. `onWebUIOpen()` est le déclencheur d'ouverture de WebUI : c'est ce qui évalue la bannière de redémarrage, propose Resume sur une transaction interrompue, et exécute la mise à jour automatique silencieuse lorsque `auto_on_webui_open` est activé.

### Source unique, ré-intégrée octet pour octet

`vdlu.js` et `vdlu.css` sont la **copie canonique**. Un module qui embarque le widget ré-intègre ces fichiers inchangés dans son `webroot/` ; il ne modifie jamais sa propre copie sur place. Une nouvelle fonctionnalité naît dans les fichiers canoniques et descend par ré-intégration. Modifier une copie intégrée produit une dérive silencieuse (c'est arrivé : une copie périmée manquait de `net_policy`, du toast DEFERRED et des champs de nouvel essai au boot). Un gardien de parité dans l'arborescence source trouve chaque copie et marque ou ré-intègre celles qui divergent, couvrant uniquement le widget ; le keyring a sa propre cadence vérifier-ne-pas-copier.

---

### API publique (`window.VDLU`)

| Fonction | Fait |
|---|---|
| `init(opts)` | configure le widget ; renvoie `window.VDLU` |
| `onWebUIOpen()` | appeler au chargement : bannière, proposition de Resume et mise à jour automatique silencieuse |
| `mountUpdatesPanel(el)` | rend le panneau Updates dans `el` (chaîne id ou élément) |
| `check()` | exécute `update.sh check` ; `Promise<{update, from, to, fetch, reboot}>` |
| `startUpdate()` | déclenche `run` en arrière-plan plus le toast de progression avec Cancel |
| `cancel()` | crée `$VDLU_DIR/cancel` (le moteur s'arrête à un point sûr) |
| `resume()` | reprend la transaction courante plus un toast |
| `refreshBanner()` | réévalue la bannière persistante de redémarrage en attente |

---

Voir aussi : [[Engine]] pour les commandes que le widget pilote, [[Quick Start]] pour les étapes complètes d'adoption, et [[Reboot Handling]] pour ce que la bannière attend.
