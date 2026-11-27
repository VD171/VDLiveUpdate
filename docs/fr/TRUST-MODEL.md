> **Languages:** [English](../TRUST-MODEL.md) · [العربية](../ar/TRUST-MODEL.md) · [Čeština](../cs/TRUST-MODEL.md) · [Deutsch](../de/TRUST-MODEL.md) · [Español](../es/TRUST-MODEL.md) · [فارسی](../fa/TRUST-MODEL.md) · Français · [हिन्दी](../hi/TRUST-MODEL.md) · [Bahasa Indonesia](../id/TRUST-MODEL.md) · [Italiano](../it/TRUST-MODEL.md) · [日本語](../ja/TRUST-MODEL.md) · [한국어](../ko/TRUST-MODEL.md) · [Nederlands](../nl/TRUST-MODEL.md) · [Polski](../pl/TRUST-MODEL.md) · [Português](../pt/TRUST-MODEL.md) · [Русский](../ru/TRUST-MODEL.md) · [Svenska](../sv/TRUST-MODEL.md) · [ไทย](../th/TRUST-MODEL.md) · [Türkçe](../tr/TRUST-MODEL.md) · [Українська](../uk/TRUST-MODEL.md) · [Tiếng Việt](../vi/TRUST-MODEL.md) · [中文](../zh/TRUST-MODEL.md)

---

# Politique de sécurité et modèle de confiance

VDLiveUpdate (VDLU) applique des **mises à jour root flashless** à un module vivant : il écrit
dans `/data/adb/modules/<mod>` et swappe un `.so` Zygisk au boot. Chaque champ d'un
manifeste récupéré (`path`, `sha256`, `delete[]`, `mode`, ...) est une **entrée hostile** - un
feed empoisonné ou un MITM le livre. Cette page est le modèle de confiance et la politique de
divulgation responsable. Pour le contrat de couture complet voir [`INTERFACES.md`](INTERFACES.md),
et les internes engine/producer dans [`ENGINE.md`](ENGINE.md) et
[`PRODUCER.md`](PRODUCER.md), la page wiki **Security-and-Trust-Model** porte le
même modèle pour les lecteurs hors du repo.

## Versions supportées

Les correctifs de sécurité arrivent dans le dernier `ENGINE_VERSION`, un manifeste signé déclare
l'engine minimum dont il a besoin via `engine_min`, et l'engine sur l'appareil refuse un manifeste
qui demande plus que ce qu'il implémente. Les engines vendorisés plus anciens sont censés
**re-vendorer** pour récupérer un correctif, pas être patchés sur place.

| ENGINE_VERSION | statut |
|---|---|
| 7 (actuel) | supporté - ne jamais revenir sur un module en avance sur le feed (le `versionCode` installé en direct sert de plancher à la version "from"), auto-réparation au boot d'un plan de downgrade obsolète |
| 6 | dépassé - auto-réparation au boot d'un journal obsolète avec `target <= 0` (le baseline 0 laissé par un stub supprimé ne déclenche plus aucune UI ni action de boot) |
| 5 | dépassé - exclusion de l'ancre de confiance côté engine (le répertoire `vdlu/` est ignoré même si un feed le porte), plafonds de 128 MiB par fichier / 2 MiB de manifeste |
| 4 | dépassé - allowlist `key_id`, rejet des paths dot-segment/trailing-slash, plafonds de taille, lock au check-time |
| <= 3 | non supporté - re-vendorer l'engine actuel |

Tout changement dans la vérification de l'engine ou la logique d'apply incrémente `ENGINE_VERSION`.

## Signaler une vulnérabilité

Signale en privé. **N'ouvre pas** d'issue, de PR ou de post de forum publics pour un bug de
sécurité. Utilise les contacts du projet (voir [`CONTRIBUTING.md`](../CONTRIBUTING.md)) :

- Telegram : **@VD_Priv8** (https://t.me/VD_Priv8)
- Canal : **@Priv8_VD** (https://t.me/Priv8_VD)
- E-mail : **vd.priv8@pm.me**

Merci d'inclure la version de l'engine, le `profile` en usage, et un manifeste ou feed qui
reproduit le problème. Les correctifs sont publiés comme un nouveau `ENGINE_VERSION` avec une entrée
`CHANGELOG.md`, coordonne le calendrier de divulgation sur le fil du signalement.

## Modèle de confiance

- **Signatures ed25519 détachées.** Le producer signe le manifeste canonique sur le
  PC (openssl), l'appareil vérifie avec l'`ed25519-mini` embarqué - **pas d'openssl sur
  l'appareil**. Le message signé est le sha256 hex du manifeste sans son champ `sig`
  (clés triées, compact, UTF-8), donc signature et verify dérivent les mêmes octets sur deux
  runtimes sans librairie JSON sur l'appareil.
- **Keyring = pubkeys RAW de 32 octets**, flash uniquement. Le keyring de l'appareil livre `<key_id>.pub`
  comme la clé raw de 32 octets (jamais le PEM), `vdlu-pack` **exclut** le keyring et les
  binaires `verify/` du feed, donc un manifeste ne peut jamais réécrire l'ancre de confiance
  sur l'appareil par le réseau.
- **Exclusion de l'ancre de confiance côté engine (VDLU#2).** Indépendamment de l'exclusion côté
  producer ci-dessus, l'engine sur l'appareil **ignore** chaque path `vdlu/` (`update.sh`,
  `vdlu-verify`, `verify/*`, `keyring/*`, config) dans un plan récupéré - il ne les récupère,
  applique, ni supprime jamais, même si un feed les porte. Un feed publié livre tout l'arbre du
  module, `vdlu/` compris, donc l'engine abandonne silencieusement ces paths plutôt que de rejeter le
  manifeste : le module se met quand même à jour, et l'ancre de confiance ne change que par un
  re-flash signé complet. Une seule clé de signature ayant fuité ne peut plus échanger le vérificateur
  ou la clé de signature par le réseau et persister root.
- **Allowlist `key_id` de module-update (fail-closed, avant la sélection de pubkey).** Un keyring
  peut légitimement porter plus d'une clé (par exemple une clé de fingerprint-feed de moindre
  confiance à côté de la clé de release). Avant même que `<key_id>.pub` soit sélectionnée, `verify_manifest`
  rejette tout manifeste dont le `key_id` n'est pas dans l'allowlist configurée, dans **les deux**
  profiles, et reflète l'ensemble résolu vers `vdlu-verify` via `VDLU_KEYID_ALLOW`. Cela
  ferme un contournement où une clé de moindre confiance ayant fuité pourrait sinon signer une
  mise à jour root flashless complète. Sûr par défaut quand `key_id` n'est pas défini : un keyring
  **à une clé** s'épingle automatiquement à cette unique clé, un keyring **multiclé** est rejeté tant que `key_id`
  n'est pas épinglé (séparé par des virgules pour la rotation).
- **La racine de confiance du fingerprint-feed est un path séparé et épinglé** avec sa propre clé, elle
  n'est jamais atteignable à travers le path de module-update ci-dessus.
- **Le baseline est une semence locale de confiance.** `baseline.json` arrive dans le zip flashé -
  la frontière de confiance de l'installation - donc il est sans signature et sans clé et **ne** passe pas par
  `vdlu-verify`, seul un manifeste **récupéré** du feed est vérifié. Cela garde la
  clé de signature hors de la CI.

## Garanties fail-closed

- **`validate_plan` tourne avant tout fetch ou apply.** Dans `do_diff`, fail-closed, il
  rejette le manifeste **entier** si un `path` est absolu, contient un segment `..` ou `.`,
  se termine par `/`, ou porte un caractère de contrôle, si un `sha256` n'est pas
  `^[0-9a-f]{64}$`, ou si un `mode`/`class`/`enc` est invalide. Aucun champ hostile n'atteint
  un shell, et `cmd_check` ne porte aucune interpolation `system()`.
- **Confinement de path.** Chaque écriture et suppression est confinée à `MODULE_DIR` via
  `contained()` - apply, delete, et le `stage_file` du reboot passent tous la même garde.
  Les symlinks dans l'arbre sont sautés par le producer (ne fuitent jamais de contenu de l'extérieur).
- **Deux profiles, fail-closed par inversion.** `trusted` (source privée, stagée par SSH) est
  le **seul** opt-in au verify best-effort, **toute** autre valeur - y compris un typo, un
  espace/CR de fin, ou une casse différente - est traitée comme `hardened`, où une signature valide
  est **obligatoire** et un échec abandonne. Le `sha256` de chaque blob est vérifié dans
  les deux profiles.
- **Signature + hash avant toute exécution d'outil.** Le `curl` statique récupéré tourne en root, donc
  `install-tool` vérifie la signature du tools-manifest (ed25519-mini, obligatoire dans **n'importe quel**
  profile) et le hash du curl **avant** qu'il soit installé et exécuté - sig+hash avant
  l'exec ferme le RCE.
- **Transaction reprenable et sûre face au pin.** Le manifeste en vol est épinglé dans `target.json` ;
  un crash, une perte réseau, ou un reboot reprend depuis le journal sans re-décider le plan.
  Le downgrade est bloqué (`version` monotone), le champ `module` signé doit égaler
  `MODID`, et `delete[]` ne tourne qu'au `finalize_done` (un `PENDING_REBOOT` ne supprime
  rien). Rien n'est jamais "fait" sans un re-hash complet, rien n'est écrasé sans
  une sauvegarde `rollback/<v>/` d'abord.

## Durcissement (défense en profondeur)

- **Plafonds de taille.** Le manifeste, le tools-manifest, et le path de téléchargement `wget`/`head -c`
  sans curl sont tous bornés avant d'être lus (anti-OOM / anti-flood). Un blob échoue
  sa phase après 3 tentatives. Les plafonds sont de **128 MiB par fichier** (`MAX_FILE_BYTES`) et
  **2 MiB pour le manifeste** (`MAX_MANIFEST_BYTES`), imposés dans `update.sh` et répliqués dans `vdlu-verify`.
- **Lock au check-time.** `check` prend le mkdir-lock avant de reconstruire son répertoire de travail, donc
  un run concurrent ne peut pas courir en course contre lui.
- **Confinement du staging.** `stage_file` a la même garde `contained()` que les primitives
  d'apply vivant, donc un path reboot-hard stagé ne peut pas s'échapper de `MODULE_DIR` non plus.
- **Le TLS est défense en profondeur, pas la racine de confiance.** Le curl statique utilise mbedTLS avec le
  trust store Android (`--capath`, override `ca_path`), la garantie d'intégrité est la
  signature ed25519, le contrôle du cert est une seconde couche.

## Voir aussi

- [`INTERFACES.md`](INTERFACES.md) - le contrat de couture immuable (§5 config, §6 signature, §11 toolchain).
- [`ENGINE.md`](ENGINE.md) - l'engine côté appareil et sa machine à états.
- [`PRODUCER.md`](PRODUCER.md) - packing, signature, canonicalisation, et rotation de clés.
- Wiki : **Security-and-Trust-Model**.

<!-- doc-footer -->

---

> _Cette documentation a été générée avec Claude (Anthropic) et est maintenue par VD171. Les corrections et améliorations sont les bienvenues, voir [CONTRIBUTING.md](CONTRIBUTING.md)._
