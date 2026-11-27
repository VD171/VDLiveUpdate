> **Languages:** [English](../AI-AGENTS.md) · [العربية](../ar/AI-AGENTS.md) · [Čeština](../cs/AI-AGENTS.md) · [Deutsch](../de/AI-AGENTS.md) · [Español](../es/AI-AGENTS.md) · [فارسی](../fa/AI-AGENTS.md) · Français · [हिन्दी](../hi/AI-AGENTS.md) · [Bahasa Indonesia](../id/AI-AGENTS.md) · [Italiano](../it/AI-AGENTS.md) · [日本語](../ja/AI-AGENTS.md) · [한국어](../ko/AI-AGENTS.md) · [Nederlands](../nl/AI-AGENTS.md) · [Polski](../pl/AI-AGENTS.md) · [Português](../pt/AI-AGENTS.md) · [Русский](../ru/AI-AGENTS.md) · [Svenska](../sv/AI-AGENTS.md) · [ไทย](../th/AI-AGENTS.md) · [Türkçe](../tr/AI-AGENTS.md) · [Українська](../uk/AI-AGENTS.md) · [Tiếng Việt](../vi/AI-AGENTS.md) · [中文](../zh/AI-AGENTS.md)

---

# Piloter VDLU depuis un agent IA

VDLiveUpdate (VDLU) est l'updater incrémental et sans flashage que les modules KSU/Magisk intègrent dans `vdlu/`. Tout le moteur se pilote depuis le shell, donc un assistant ou agent IA peut vérifier, appliquer, reprendre et finaliser une mise à jour en mode headless, le même cycle que celui de la WebUI, sans UI et sans humain dans la boucle. Analysez le JSON qu'il imprime, ne scrapez jamais le texte.

## Le contrat

Un seul point d'entrée, exécuté en root sur l'appareil, avec les trois variables d'environnement du moteur définies:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <verb>
```

- `VDLU_DIR` est le répertoire d'état Tier-2 (hors du module, survit à un reflash), `MODULE_DIR` est l'arbre vivant du module, `MODID` est l'id du module.
- `rc 0` = ok, `rc != 0` = erreur, avec la raison sur stderr.
- Les verbes de lecture (`check`, `status`) impriment **un objet JSON** sur stdout. Analysez-le, ne scrapez jamais le texte.
- Le moteur ne dépend que de toybox (`sha256sum`/`gzip`/`base64`) plus un `ed25519-mini` embarqué plus un `curl` statique récupéré à la première mise à jour https, zéro `jq`.

Pendant le développement le même script se trouve dans `engine/update.sh` dans ce dépôt, donc `sh engine/update.sh <verb>` avec les trois variables définies pilote une copie de test de la même manière.

## Verbes

| Verbe | Fait | Imprime |
|------|------|--------|
| `check` | DIFF en lecture seule contre le flux, ne change rien | `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`, ou `{"update":false,"ahead":true,"from":N,"to":M}` quand l'appareil est en avance sur le flux (downgrade bloqué, bénin, rc 0) |
| `run` | cycle LIVE complet DIFF -> FETCH -> APPLY -> COMMIT, applique les fichiers LIVE et met en scène les REBOOT-hard, respecte `cancel` | progression dans `journal.json` |
| `resume` | reprend la transaction en attente depuis sa phase actuelle, idempotent, ne remplace jamais le `.so` | `journal.json` mis à jour |
| `boot` | mode pre-zygote, `resume` plus l'échange du `.so` mis en scène, ferme `PENDING_REBOOT` en `DONE` | `journal.json` mis à jour |
| `status` | instantané en lecture seule, ne change rien | `journal.json`, ou `{"state":"idle"}` quand aucune transaction n'est active |
| `cancel` | demande un arrêt, un `run` en cours s'arrête au prochain point sûr | crée `$VDLU_DIR/cancel` |

Une mise à jour headless, c'est `check` pour voir s'il y a quelque chose en attente, `run` pour appliquer tout ce qui peut passer en direct, puis `boot` au prochain démarrage pour échanger tout `.so` mis en scène (ou `resume` pour réessayer un fetch différé). Chaque verbe est sûr à rappeler, un plantage ou une coupure réseau en milieu de cycle laisse un journal reprenable, jamais un module à moitié appliqué.

## JSON de statut

`status` (et le fichier vivant dans `$VDLU_DIR/journal.json`) est le contrat de progression que la WebUI et un agent lisent tous deux:

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit",
  "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>,
  "reboot_pending":bool, "cancelled":bool, "error":"<str|null>",
  "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

- `state` avance dans un ordre fixe: `PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)`.
- `DONE` n'est atteint qu'une fois qu'un re-hash de tout correspond. Un fichier REBOOT-hard mis en scène donne `PENDING_REBOOT`, jamais un `DONE` bidon, lancez `boot` pour le terminer.
- `DEFERRED` signifie que `net_policy` a bloqué le téléchargement, un état bénin et reprenable et non une erreur, le plan persiste et le prochain `check`/`boot` continue.
- `ERROR` porte la raison dans `error`, les fichiers LIVE appliqués sont annulés depuis `rollback/`, le module n'est jamais laissé à moitié appliqué.
- `cancelled:true` avec `error:null` est un arrêt propre, le journal reste reprenable.

## Le contrat de couture

Chaque composant (moteur, producteur, WebUI) se conforme à [`INTERFACES.md`](INTERFACES.md), la loi de convergence. Les verbes de la CLI, le schéma du `manifest.json`, les clés du `journal.json` et les clés de config qui y sont définies sont **immuables**, traitez ce fichier comme la seule source de vérité et alignez-vous dessus avant de changer l'un d'eux. Pour les internes du moteur (la transaction reprenable, les garanties de rigueur, l'exclusion du trust-anchor) voir [`ENGINE.md`](ENGINE.md), pour le côté flux (construire et signer le flux adressé par contenu) voir [`PRODUCER.md`](PRODUCER.md).

## Règles pour un agent

- Utilisez les verbes et le JSON, ne scrapez jamais la WebUI et ne modifiez jamais les fichiers d'état à la main.
- Traitez `INTERFACES.md` comme immuable, un changement veut dire aligner le contrat d'abord.
- Un patch d'un agent IA passe la même barre de revue que n'importe quel autre, build toujours release, ne relâchez rien, ne perdez rien.

<!-- doc-footer -->

---

> _Cette documentation a été générée avec Claude (Anthropic) et est maintenue par VD171. Les corrections et améliorations sont les bienvenues, voir [CONTRIBUTING.md](CONTRIBUTING.md)._
