> **Languages:** [English](../../SECURITY.md) · [العربية](../ar/SECURITY.md) · [Čeština](../cs/SECURITY.md) · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · [فارسی](../fa/SECURITY.md) · Français · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · [Italiano](../it/SECURITY.md) · [日本語](../ja/SECURITY.md) · [한국어](../ko/SECURITY.md) · [Nederlands](../nl/SECURITY.md) · [Polski](../pl/SECURITY.md) · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · [中文](../zh/SECURITY.md)

---

# Politique de sécurité

VDLiveUpdate (VDLU) applique des mises à jour flashless avec root à un module en cours
d'exécution : il écrit dans le répertoire du module lui-même et remplace un `.so` Zygisk
au démarrage, en s'exécutant dans le contexte root du module. Nous prenons la sécurité au
sérieux.

## Signaler une vulnérabilité

- **Site:** https://vd171.ru
- **Site:** https://vd.priv8.ru
- **Issues:** https://github.com/VD171/VDLiveUpdate/issues
- **GitHub:** [@VD171](https://github.com/VD171)
- **XDA-Developers:** [@VD171](https://xdaforums.com/m/vd171.4699873/)
- **Telegram:** [@VD_Priv8](https://t.me/VD_Priv8)
- **Channel:** [@Priv8_VD](https://t.me/Priv8_VD)
- **Discord:** [@VD.Priv8](https://discord.com/users/1296831918989639721)
- **E-mail:** vd.priv8@pm.me

Incluez une description claire et, si possible, un manifeste ou un feed qui reproduit le
problème. Nous répondrons dès que possible et nous vous créditerons si vous le souhaitez.

## Notes de portée

- Les mises à jour sont des blobs content-addressed ainsi qu'un `manifest.json` signé avec
  ed25519. L'appareil vérifie la signature avec un `ed25519-mini` intégré (pas d'openssl
  sur l'appareil), et chaque blob est contrôlé par rapport à son `sha256` avant d'être
  utilisé.
- Le profil hardened (la valeur par défaut publique) exige une signature valide et bloque
  le downgrade. La version "de départ" est plafonnée par le `versionCode` du module
  installé (lu depuis `module.prop`), de sorte qu'un module n'est jamais ramené derrière le
  feed.
- La racine de confiance (la clé publique ed25519 brute du `keyring/` et les binaires de
  `verify/`) est flash-only et n'est jamais renouvelée par le réseau. Le producteur
  l'exclut du feed et l'engine ignore tout chemin `vdlu/` dans un plan téléchargé, de sorte
  qu'une clé de signature divulguée ne peut pas remplacer le vérificateur ou la clé et
  persister en root.
- Un manifeste valablement signé pour un autre module ne peut pas écrire dans le répertoire
  d'un module différent. Le champ `module` signé doit être égal au `MODID` de l'appareil
  (vérification de liaison entre modules), et toute écriture et suppression reste confinée
  au répertoire du module.
- L'engine s'exécute dans le propre contexte root du module et ne l'affaiblit jamais. Il
  n'ajoute aucun privilège et n'interpole aucun champ du manifeste dans un shell, chaque
  valeur de `path`, `sha256`, `mode` et `delete[]` est validée comme entrée hostile avant
  utilisation.
- La posture est fail-closed. Une valeur de `profile` corrompue ou inconnue ne glisse
  jamais vers l'acceptation de contenu non signé (tout ce qui n'est pas exactement
  `trusted` est traité comme `hardened`), et une sauvegarde est écrite avant qu'un fichier
  ne soit écrasé, de sorte qu'un apply en échec ne détruit jamais la version installée.
- Voir [TRUST-MODEL.md](TRUST-MODEL.md) pour le modèle de confiance complet, les garanties
  fail-closed et les détails de hardening.

<!-- doc-footer -->

---

> _Cette documentation a été générée avec Claude (Anthropic) et est maintenue par VD171. Les corrections et améliorations sont les bienvenues, voir [CONTRIBUTING.md](CONTRIBUTING.md)._
