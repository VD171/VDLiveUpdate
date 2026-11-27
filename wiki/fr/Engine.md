# Engine

Le moteur est le côté appareil de VDLU : la partie qui s'exécute sur le téléphone, décide de ce qui a changé, le télécharge et l'applique. C'est un unique script shell POSIX, `engine/update.sh`, plus un minuscule vérificateur de signature, `engine/vdlu-verify`. Les deux sont intégrés au module hôte dans `<module>/vdlu/` et exécutés par root.

Tout le moteur est bâti autour d'une seule idée : une mise à jour est une **transaction reprenable**. Si le téléphone est redémarré, tué, ou perd le réseau à mi-chemin, l'exécution suivante reprend exactement là où elle s'est arrêtée, et le module n'est jamais laissé appliqué à moitié en prétendant être terminé.

Si vous voulez d'abord la vue d'ensemble, voir [[Architecture]]. Pour savoir comment les mises à jour évitent un redémarrage chaque fois qu'elles le peuvent, voir [[Reboot Handling]].

## Écrit pour l'appareil, pas pour votre ordinateur portable

`update.sh` est du `sh` POSIX pur. Il tourne sous mksh, busybox ou toybox, sans fonctionnalités propres à bash, et passe `sh -n`. Cela compte parce que l'environnement sur un appareil Android rooté est petit et strict.

En particulier, il n'y a pas de `jq`. VDLU analyse `manifest.json` avec un petit aplatisseur de style gron écrit en `awk` : il parcourt le JSON un caractère à la fois et émet une ligne `path<TAB>value` par feuille (par exemple `files/0/sha256<TAB>ab..` ou `version<TAB>6`). Le shell lit ensuite ces lignes avec `grep` et `cut`. Cela fonctionne sur du JSON compact comme sur du JSON formaté, et ne fait jamais appel à un outil JSON qui n'est pas là.

Le moteur ne dépend que de ce que toybox livre déjà (`sha256sum`, `gzip`/`gunzip`, `base64`, `date`), du vérificateur `ed25519-mini` embarqué, et, pour les feeds `https://`, d'un petit `curl` statique récupéré et vérifié une fois. Un feed `file://` n'a besoin d'aucun `curl`.

## Les six commandes

Vous invoquez le moteur avec les chemins du module dans l'environnement et une commande :

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <cmd>
```

Le code de sortie `0` signifie succès ; tout autre code signifie une erreur, avec la raison imprimée sur stderr.

| Commande | Ce qu'elle fait |
|---|---|
| `check` | Diff en lecture seule. Télécharge le manifeste, le compare à l'installé, et imprime un résumé JSON sur une ligne : `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`. Ne change rien sur le disque. Si l'appareil est plus récent que le feed (un downgrade bloqué) il rapporte `{"update":false,"ahead":true,...}` avec sortie `0`, pas une erreur. |
| `run` | Le cycle en direct complet : DIFF, FETCH, APPLY, COMMIT. Applique chaque fichier en direct immédiatement et échelonne les rares fichiers de classe reboot. Respecte `cancel`. Écrit la progression dans `journal.json`. |
| `resume` | Continue une transaction interrompue, en partant de la phase où elle se trouvait. Idempotent. Il **n'**échange **pas** un `.so` échelonné (cela est réservé à `boot`). |
| `boot` | Le chemin pré-zygote. Effectue un `resume` puis échange tout fichier `*.vdlu-new` échelonné en place, fermant `PENDING_REBOOT` vers `DONE`. S'il n'y a aucune transaction en attente, il exécute un cycle neuf et applique tout, y compris le `.so`, lors de ce seul démarrage. |
| `status` | Imprime `journal.json`, ou `{"state":"idle"}` lorsqu'il n'y a rien en cours. |
| `cancel` | Crée un marqueur `cancel`. Un `run` en cours s'arrête proprement au prochain point sûr. |

La commande `check` est délibérément peu coûteuse, afin que l'UI puisse vous indiquer qu'une mise à jour existe sur n'importe quel réseau. Le téléchargement réel est géré séparément (voir la phase fetch ci-dessous).

## La transaction, étape par étape

Chaque `run` traverse une machine à états fixe, enregistrée dans `journal.json` afin que la WebUI (et vous) puissiez l'observer :

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

**DIFF.** Le moteur récupère `manifest.json`, valide chaque champ (voir ci-dessous et [[Security and Trust Model]]), et compare l'arborescence cible signée à `current.json`, le manifeste de la version déjà installée. Le résultat est un plan fichier par fichier écrit dans `plan.tsv` : une ligne par fichier, portant sa classe, son hachage cible, son mode et son état de progression. Les fichiers déjà au hachage cible sont marqués à sauter.

**FETCH.** Pour chaque fichier encore nécessaire, le moteur télécharge son blob adressé par contenu depuis `<source>/blobs/<sha>` (ou `<sha>.gz` quand compressé), vers un fichier `.part`. Si le blob est compressé en gzip il est décompressé, puis son SHA-256 est vérifié par rapport au manifeste. Ce n'est qu'en cas de correspondance qu'il est déplacé de manière atomique (`mv`) vers `blobs/<sha>`. Un blob déjà en cache avec un hachage correct est entièrement sauté, et un fichier local inchangé peut amorcer le cache sans aucun téléchargement. Trois échecs sur le même blob interrompent la phase sans rien appliquer. La phase atteint `FETCHED` seulement lorsque chaque blob du plan est présent et vérifié. Pour le [[Feed Format]] d'où proviennent ces blobs, voir cette page. À la configuration du toolchain le moteur journalise la confiance TLS résolue - le chemin de la CA et s'il est lisible, plus la taille du bundle et le nombre de certificats - de sorte qu'un `rc 77` de curl au boot soit auto-explicatif dans `boot.log` (il distingue un trust store vide d'un illisible, le cas du contexte SELinux de boot).

Le fetch est géré par la politique réseau : un feed peut être restreint au Wi-Fi seul, au mobile seul, ou à n'importe quel réseau. Lorsque le réseau courant n'est pas autorisé, le fetch n'échoue pas ; il entre dans l'état bénin `DEFERRED`, conserve le plan et la cible épinglés, et reprend au prochain check ou démarrage lorsque le bon réseau apparaît. Aucune donnée n'est dépensée entre-temps.

**APPLY.** N'est jamais atteint que depuis `FETCHED`. Pour chaque fichier le moteur agit selon la classe :

- Fichiers `live` et `soft` : sauvegarder le fichier courant vers `rollback/<version>/<path>`, écrire le nouveau contenu dans un frère `.vdlu-tmp`, lui faire un `chmod`, vérifier son hachage, puis le `rename` de manière atomique par-dessus la cible. Un fichier déjà au hachage cible est sauté.
- Fichiers `reboot` (un `.so`, un overlay `/system`, un `sepolicy.rule`) : matérialiser dans `staged/<path>.vdlu-new`. L'inode en direct n'est jamais touché ici. Voir [[Reboot Handling]].
- suppressions : sauvegarder, puis supprimer. Les suppressions ne sont appliquées qu'à la toute fin, sur un `DONE` propre, jamais tant qu'un redémarrage est encore en attente.

**COMMIT.** Le moteur re-hache chaque fichier `live` et `soft` qu'il a touché. Ce n'est que lorsque tous correspondent qu'il écrit `current.json`, faisant de la nouvelle version la base du diff. Si un fichier de classe reboot a été échelonné, l'état devient `PENDING_REBOOT` au lieu de `DONE` ; l'échange et la re-vérification finale ont lieu plus tard sous la commande `boot`.

## Fail-safe par construction

Les garanties qui le rendent sûr à exécuter sans surveillance :

- **Rien n'est marqué `DONE` sans un re-hachage concordant.** `DONE` n'est atteint qu'après que chaque fichier appliqué a été relu et son SHA-256 comparé au manifeste. Un fichier reboot échelonné force `PENDING_REBOOT`, jamais un `DONE` factice.
- **Rien n'est perdu.** Chaque fichier est sauvegardé vers `rollback/<version>/` avant d'être écrasé, et les trois dernières versions sont conservées. Si un apply échoue, les fichiers en direct sont revenus depuis la sauvegarde ; le module n'est jamais laissé appliqué à moitié en mentant à ce sujet. `apply_live` interrompt purement et simplement si l'étape de sauvegarde échoue, plutôt que d'écraser sans retour possible.
- **Tout est atomique.** Le nouveau contenu atterrit via `rename`/`mv` par-dessus la cible, de sorte qu'un lecteur voit toujours soit l'ancien fichier soit le nouveau, jamais une écriture tronquée.
- **Reprenable après une panne ou un kill.** Une panne, une coupure réseau ou un redémarrage à mi-chemin laisse un journal valide ; `resume` (ou `boot`) continue depuis la phase enregistrée. La conception suppose qu'elle sera interrompue.
- **Se dégrade proprement.** Un binaire manquant, un réseau coupé ou un disque plein produit une erreur claire sur stderr et `state:ERROR` dans le journal, sans corrompre le module.
- **L'ancre de confiance est exclue (`ENGINE_VERSION` 5).** Le moteur ignore chaque chemin `vdlu/` dans un plan récupéré - ses propres `update.sh`, `vdlu-verify`, les binaires `verify/`, le keyring et la config - de sorte qu'un feed ne peut jamais échanger le vérificateur ou la clé de signature par le réseau ; l'ancre ne change que par un re-flash signé complet. Voir [[Security and Trust Model]].
- **Une mise à jour est différée pendant que le module est occupé.** Avec l'option `apply_busy_file` définie à un chemin absolu que le module hôte touche pendant ses propres opérations (par exemple une sauvegarde en cours), APPLY attend tant que ce chemin existe, de sorte que les fichiers ne sont jamais échangés en pleine opération ; les blobs sont déjà récupérés, donc le prochain trigger applique sans re-téléchargement.
- **Plafonds de taille.** Un fichier est plafonné à **128 MiB** et le manifeste à **2 MiB**, imposés avant que l'un ou l'autre ne soit lu, dans `update.sh` comme dans `vdlu-verify` (anti decompression-bomb / anti-OOM).
- **Un module en avance sur le feed n'est jamais rétabli (`ENGINE_VERSION` 7).** Le `versionCode` installé en direct, lu depuis le propre `module.prop` du module, sert de plancher à la version "from", donc un appareil mis à jour manuellement au-delà d'un feed obsolète est lu comme *en avance* : la garde de downgrade renvoie bénin, sans plan ni retour arrière. `boot` auto-répare aussi une installation existante - un plan persisté dont le target est sous la version installée, ou un journal obsolète avec `target <= 0` (`ENGINE_VERSION` 6), est effacé avant tout resume.

## Le verrou

Une seule transaction peut toucher l'état à la fois. `flock` n'est pas fiable sur toybox, aussi VDLU sérialise avec un verrou de répertoire : `mkdir "$VDLU_DIR/lock.d"` réussit pour exactement un appelant et échoue pour les autres, ce qui est atomique sur tout système de fichiers raisonnable. Un verrou périmé laissé par un processus mort est récupéré en vérifiant le PID enregistré.

Le nouvel essai patient au démarrage (utilisé lorsque l'appareil est hors ligne au boot) ne **détient pas** ce verrou pendant qu'il attend. Il l'acquiert et le libère entre les tentatives, de sorte qu'un `run` manuel n'est jamais bloqué par un boot qui attend le réseau, et il ne détient jamais de wakelock. Sûr pour la batterie par conception. Plus de détails dans [[Reboot Handling]].

## Vérification de signature : `vdlu-verify`

`vdlu-verify` est le vérificateur de signature sur l'appareil, maintenu délibérément mince :

```
vdlu-verify <manifest.json> <keyring_dir>
```

La sortie `0` signifie que la signature du manifeste est valide par rapport à la clé publique du keyring dont l'id correspond au `key_id` du manifeste ; tout autre code est un rejet.

Ce qui le rend mince, c'est qu'il n'utilise **aucun `openssl` sur l'appareil**. Il lit la clé publique du keyring comme un fichier de **32 octets bruts**, canonicalise le manifeste (le texte du manifeste avec le champ `sig` retiré), le hache avec le `sha256sum` de toybox, décode en base64 la signature, et transmet la clé brute, le message et la signature de 64 octets au binaire `ed25519-mini` embarqué. Le vérificateur refuse aussi tout élément malformé avant même de vérifier : un `key_id` ou `sig` manquant ou vide, un `key_id` contenant des séparateurs de chemin, une clé publique qui ne fait pas exactement 32 octets, ou une signature qui ne fait pas exactement 64 octets.

Avant même de sélectionner une clé, le moteur applique une **liste d'autorisation de `key_id`** : le `key_id` du manifeste doit être une clé que la config autorise à signer une *mise à jour de module*, et une clé simplement présente dans le keyring mais non autorisée est rejetée avant que sa clé publique ne soit jamais chargée. Un keyring à clé unique épingle automatiquement cette seule clé sans config ; un keyring à plusieurs clés doit épingler `key_id` ou le moteur échoue en mode fermé. L'ensemble autorisé est transmis à `vdlu-verify` via `VDLU_KEYID_ALLOW`, et il s'applique dans les deux profils. Cela empêche une clé de moindre confiance, comme une clé de feed de fingerprint partageant le keyring, de signer une mise à jour root complète ; le feed de fingerprint séparé garde sa propre clé épinglée, `FEED_KEY_ID`. L'histoire complète figure dans [[Security and Trust Model]].

La canonicalisation est identique octet pour octet à celle du signataire du producteur, ce qui fait qu'une signature se vérifie d'un outil à l'autre. La clé privée correspondante ne touche jamais un appareil ni la CI ; seule la clé publique brute est embarquée. L'histoire complète de confiance, les deux profils et la raison pour laquelle `hardened` est fail-closed par inversion figurent dans [[Security and Trust Model]].

Le moteur appelle `vdlu-verify` pendant la phase diff. Sous le profil `hardened` une vérification en échec interrompt toute la mise à jour ; sous `trusted` la vérification est au mieux (best-effort), mais le hachage de chaque blob est toujours vérifié de toute façon, de sorte qu'un contenu corrompu est détecté quel que soit le profil.

## État sur disque

Tout l'état du moteur vit dans `$VDLU_DIR` (hors du répertoire du module), de sorte que l'arborescence du module elle-même ne contient jamais que des fichiers terminés :

| Chemin | Rôle |
|---|---|
| `config` | paramètres clé=valeur (source, profile, channel, politique réseau, nouvel essai au boot) |
| `current.json` | manifeste de la version active ; c'est la base du diff. Absent signifie jamais mis à jour |
| `target.json` | le manifeste épinglé de la transaction en cours. Sa présence marque une transaction active ; il devient `current.json` sur `DONE` |
| `plan.tsv` / `plan.del` | le plan fichier par fichier et la progression, et la liste des chemins à supprimer |
| `journal.json` | progression pour la WebUI, réécrit à chaque changement d'état |
| `blobs/<sha256>` | cache de contenu original vérifié et décompressé |
| `rollback/<version>/<path>` | sauvegardes des fichiers écrasés ; les trois dernières versions sont conservées |
| `staged/<path>.vdlu-new` | un fichier de classe reboot en attente de l'échange au démarrage |
| `lock.d/` | le verrou mkdir |
| `tools/<abi>/curl` | le curl statique récupéré et vérifié ; persiste d'une mise à jour à l'autre |
| `cancel` | une demande d'annulation |

## Voir aussi

- [[Reboot Handling]] : comment le système de classes garde la plupart des mises à jour sans redémarrage, et comment un `.so` échelonné est échangé pré-zygote.
- [[Security and Trust Model]] : les deux profils, la validation fail-closed et la chaîne ed25519 à clé brute.
- [[Feed Format]] : le manifeste et les blobs adressés par contenu que le moteur consomme.
- [[Architecture]] : comment le moteur, le producteur et la WebUI s'imbriquent.
