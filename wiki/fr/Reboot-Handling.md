# Reboot Handling

Tout l'intérêt de VDLU est de mettre à jour un module sans le reflasher, et, autant que possible, sans redémarrer du tout. La plupart des fichiers d'un module peuvent être remplacés pendant que l'appareil fonctionne. Quelques-uns, vraiment, ne le peuvent pas, parce que le noyau ou le processus zygote les a déjà mappés et ne remarquera pas un changement avant le prochain démarrage.

Le rôle de VDLU est de distinguer ces deux groupes automatiquement, d'appliquer en toute sécurité tout ce qu'il peut **en direct**, et de ne différer que les fichiers réellement liés au démarrage vers un redémarrage qu'il signale clairement. Cette page explique comment.

Pour la mécanique du moteur en dessous, voir [[Engine]]. Pour la vue d'ensemble, voir [[Architecture]].

## Pourquoi ne pas simplement redémarrer à chaque fois

Un redémarrage est la chose la plus coûteuse qu'une mise à jour puisse demander à quelqu'un. Il interrompt ce qu'il est en train de faire, il prend une minute ou plus, et il habitue les gens à redouter les mises à jour. Un bon outil de mise à jour incrémentale devrait sembler invisible : vous touchez mettre à jour, quelques fichiers changent sous le système en cours d'exécution, et vous êtes déjà sur la nouvelle version.

Aussi VDLU inverse l'hypothèse habituelle. Le défaut est en direct. Un fichier n'est différé vers un redémarrage que lorsqu'il est prouvablement l'un des types liés au noyau ou au zygote, et même alors seul ce fichier attend. Tout ce qui l'entoure se met encore à jour immédiatement.

## Les trois classes

À chaque fichier du feed est assignée une classe. Le producteur peut la définir explicitement dans le manifeste, mais en pratique la classe est dérivée du chemin, et le moteur ne fera jamais qu'élever un fichier vers `reboot`, jamais l'abaisser vers `live`. Les classes sont :

**LIVE** est le cas courant : assets de la web UI, binaires, scripts lus à la demande, fichiers de config, `module.prop`, et tout ce qui n'est pas apparié par les règles ci-dessous. Un fichier live est sauvegardé puis renommé de manière atomique par-dessus la cible pendant que le système fonctionne. Pas de redémarrage, et le changement est en vigueur à l'instant où le rename atterrit.

**SOFT** correspond aux scripts de cycle de vie propres au module : `service.sh`, `post-fs-data.sh` et `boot-completed.sh`. Ceux-là sont appliqués en direct exactement comme les fichiers LIVE, de sorte que la nouvelle copie est déjà sur le disque. La raison pour laquelle ils ont leur propre classe est que le système en cours d'exécution a déjà exécuté l'ancienne copie lors de ce démarrage ; la nouvelle s'exécute simplement au prochain démarrage, sans échelonnement et sans bannière. Il n'y a rien à différer, juste une passation naturelle.

**REBOOT-hard** est le petit ensemble qui ne peut pas changer sous un système en cours d'exécution :

- bibliothèques natives, `*.so` (tout ce qui est sous un chemin `zygisk/`), parce que zygote les mappe dans chaque app au démarrage ;
- fichiers d'overlay `/system`, parce que l'overlay est monté au démarrage ;
- fichiers `sepolicy.rule`, parce que la politique SELinux est chargée tôt.

Un fichier REBOOT-hard n'est jamais écrit par-dessus son inode en direct pendant que le système est en marche. Écraser un `.so` que zygote a déjà mappé est la façon d'obtenir des plantages et un état incohérent. À la place, le nouveau contenu est **échelonné** à côté du répertoire d'état et échangé au prochain démarrage, avant que quoi que ce soit ne puisse le mapper.

## Du chemin à la classe, d'un coup d'oeil

Le moteur dérive la classe du chemin ainsi :

| Motif de chemin | Classe | Appliqué |
|---|---|---|
| `zygisk/**`, `**/zygisk/**` (les fichiers `.so`) | REBOOT-hard | échelonné, échangé pré-zygote au démarrage |
| `system/**` (overlay) | REBOOT-hard | échelonné, échangé au démarrage |
| `*.rule` (sepolicy) | REBOOT-hard | échelonné, échangé au démarrage |
| `service.sh`, `post-fs-data.sh`, `boot-completed.sh` | SOFT | écrit en direct, s'exécute au prochain démarrage |
| `webroot/**`, `bin/**`, `lib/**`, configs, `module.prop`, tout le reste | LIVE | écrit en direct, effectif immédiatement |

Le manifeste peut porter une `class` explicite par fichier, mais la classe dérivée agit comme un plancher : si un fichier a l'air REBOOT-hard par son chemin, il est traité comme REBOOT-hard même si le manifeste dit le contraire. Cela empêche un feed mal étiqueté de jamais tenter un hot-swap d'un `.so`.

## Comment une exécution gère les deux groupes à la fois

Pendant un `run` normal (le cycle DIFF à FETCH à APPLY à COMMIT décrit dans [[Engine]]), les deux groupes sont gérés dans la même transaction :

```
run:
  LIVE + SOFT  --> backup -> write .vdlu-tmp -> verify -> atomic rename   (effective now)
  REBOOT-hard  --> materialize into staged/<path>.vdlu-new                (live inode untouched)

  re-hash every LIVE + SOFT file
       |
       +-- nothing staged  --> DONE
       +-- something staged --> PENDING_REBOOT  (reboot banner in the WebUI)
```

Ainsi après une exécution qui a touché un `.so`, vous êtes déjà sur la nouvelle version pour chaque fichier en direct, et seules les pièces échelonnées attendent. Le journal rapporte `reboot_pending`, et la WebUI affiche une bannière persistante invitant à un redémarrage pour activer les fichiers échelonnés. Il n'y a pas de "done" factice : une exécution avec des fichiers échelonnés se termine en `PENDING_REBOOT`, pas en `DONE`.

## L'échange au démarrage

Les fichiers échelonnés sont appliqués par la commande `boot`, que le module hôte branche dans `post-fs-data.sh` afin qu'elle s'exécute de manière synchrone et **pré-zygote**, avant qu'aucun processus ne puisse mapper le nouveau `.so`.

`boot` effectue un `resume` (pour terminer toute phase interrompue) puis l'échange. Pour chaque fichier REBOOT-hard échelonné il :

1. confirme que le chemin échelonné reste à l'intérieur du répertoire du module (une vérification de confinement) ;
2. re-hache `staged/<path>.vdlu-new` contre le hachage du manifeste ;
3. sauvegarde le fichier en direct courant ;
4. fait un `mv -f` du fichier échelonné par-dessus celui en direct et lui fait un `chmod` ;
5. re-hache le fichier maintenant en place, pour confirmer que l'échange a atterri correctement ;
6. le marque comme appliqué.

Ce n'est qu'une fois que chaque fichier échelonné a été échangé et re-vérifié que la transaction se ferme de `PENDING_REBOOT` vers `DONE`. Si une étape échoue, le journal enregistre l'erreur et le module garde ses fichiers précédents ; rien n'est laissé échangé à moitié.

Parce que l'échange est une séquence de re-hachages et de renames atomiques, exécuter `boot` est sûr même s'il a été interrompu la fois précédente. Il reprend simplement les fichiers échelonnés.

## auto_on_reboot

L'échelonnement n'est que la moitié d'une sensation sans redémarrage ; l'autre moitié est que l'utilisateur ne devrait jamais avoir à se souvenir d'exécuter l'échange. Avec `auto_on_reboot=1` dans la config, le `post-fs-data.sh` du module hôte appelle `update.sh boot` à chaque démarrage. Cela signifie :

- si une transaction est en attente de redémarrage, les fichiers échelonnés sont échangés automatiquement avant que zygote ne démarre, et l'utilisateur se retrouve simplement pleinement sur la nouvelle version ;
- s'il n'y a rien en attente, `boot` peut exécuter un cycle neuf et appliquer tout, y compris un `.so`, lors de ce seul démarrage, puisqu'il tourne déjà en pré-zygote.

En d'autres termes, un `.so` échelonné ne coûte à l'utilisateur rien de plus qu'un redémarrage qu'il allait faire de toute façon. Il n'a rien à toucher la seconde fois.

## Hors ligne au démarrage, sans vider la batterie

Parfois `boot` veut vérifier le feed mais l'appareil n'a pas encore de réseau. VDLU peut l'attendre, patiemment et à moindre coût, contrôlé par `boot_retry_minutes` (0 le désactive). L'attente est délibérément sûre pour la batterie :

- entre les tentatives il fait simplement `sleep`, qui se fige en sommeil profond, de sorte que l'appareil dort normalement et le nouvel essai ne reprend qu'une fois l'appareil déjà réveillé ;
- il ne détient aucun wakelock et ne détient pas le verrou du moteur pendant l'attente, de sorte qu'une exécution manuelle n'est jamais bloquée ;
- avant chaque tentative il vérifie si le réseau est autorisé avec une recherche de route noyau qui n'envoie aucun paquet et ne réveille pas la radio ;
- il ne réessaie jamais un échec déterministe comme une mauvaise signature ou un downgrade bloqué, seulement une condition génuine d'absence de réseau.

La vérification du manifeste elle-même reste gratuite sur n'importe quel réseau, de sorte que vous apprenez toujours qu'une mise à jour existe ; seul le téléchargement attend que la politique réseau soit satisfaite, en se différant proprement plutôt qu'en erreur.

## Voir aussi

- [[Engine]] : la transaction, la logique d'apply-par-classe et la commande `boot` en détail.
- [[Architecture]] : où se situe le moteur parmi le producteur et la WebUI.
