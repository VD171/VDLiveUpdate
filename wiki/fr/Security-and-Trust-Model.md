# Security and Trust Model

VDLU met à jour un module sur place, par le réseau, en tant que root. C'est beaucoup de pouvoir pointé vers un fichier qui provient d'un feed, aussi tout le moteur repose sur une unique hypothèse :

> **Chaque champ du manifeste est une entrée hostile.**

Un feed peut être empoisonné à la source, ou échangé et malmené en transit par un MITM. Lorsque cela arrive, le manifeste arrive quand même en ressemblant à un manifeste : il porte des chemins de fichiers, des chaînes `sha256`, une liste `delete[]`, des modes, des classes et un drapeau d'encodage. VDLU n'en traite aucun comme digne de confiance. Il valide le plan entier avant de télécharger le moindre octet, et il ne laisse jamais une valeur du manifeste atteindre un shell.

Cette page est l'histoire complète de confiance. Voir [[Feed Format]] pour le schéma de manifeste qu'elle valide, et [[Engine]] pour l'emplacement de ces vérifications dans la transaction DIFF -> FETCH -> APPLY -> COMMIT.

---

## L'idée centrale : fail-closed, avant que quoi que ce soit ne se produise

`validate_plan()` s'exécute dans la phase `check`/diff, **avant** tout fetch et **avant** tout apply. Il parcourt chaque entrée de l'arborescence de fichiers planifiée et chaque entrée de `delete[]`, et si une seule entrée est malformée il **rejette le manifeste entier** et la transaction ne démarre jamais. Il n'y a pas d'acceptation partielle, pas de "sauter le mauvais et appliquer le reste". Un seul champ invalide empoisonne le lot, à dessein.

Un manifeste n'est accepté que si **toutes** ces conditions sont vraies pour **chaque** entrée :

| Champ | Règle | Pourquoi |
|---|---|---|
| `path` | non absolu, aucun composant `..`, aucun composant `.`, aucun `./` initial, aucun `/./` incorporé, aucun slash final, aucun caractère de contrôle (tab / newline) | un chemin doit rester à l'intérieur de `MODULE_DIR` ; un chemin absolu ou `..` est écrire-n'importe-où |
| `sha256` | correspond exactement à `^[0-9a-f]{64}$` | un sha non hex serait sinon interpolé dans un chemin shell ; c'est l'adresse de contenu, donc ce doit être un condensé hex pur et rien d'autre |
| `mode` | octal uniquement (`[0-7]`) | une chaîne de mode devient un argument de `chmod` |
| `size` | chiffres uniquement, et `<=` au plafond de taille du moteur | borne le téléchargement et la décompression |
| `class` | exactement `live`, `soft` ou `reboot` | la classe décide si un fichier s'applique en direct ou est échelonné pour redémarrage |
| `enc` | exactement `raw` ou `gz` | l'encodage décide si le blob est décompressé en gunzip |
| entrées de `delete[]` | les mêmes règles de chemin que ci-dessus | une entrée de `delete[]` pilote une suppression ; un `..` non vérifié ferait un `rm` hors de l'arborescence |

Parce que cela s'exécute en premier, un manifeste empoisonné ne peut jamais écrire hors du module, jamais supprimer hors du module, et jamais injecter un token non hex dans une ligne de commande.

### Les valeurs du manifeste ne touchent jamais un shell

La seconde moitié de la règle : même après qu'une valeur a passé la validation, elle n'est jamais interpolée dans `sh`, et jamais fournie à `awk system()`. La commande check a été délibérément réécrite pour ne contenir aucun appel `system()`. L'adressage par contenu fait le reste du travail : un blob est récupéré par son `sha256`, écrit vers un chemin de cache nommé par ce même `sha256`, et les octets téléchargés sont re-hachés et comparés avant que quoi que ce soit ne soit appliqué. Une valeur qui n'est pas un condensé propre de 64 hex n'arrive jamais aussi loin, parce que `validate_plan()` l'a déjà rejetée.

### Une seconde ligne de défense au moment de l'apply

`validate_plan()` bloque `..` **lexicalement**, mais un lien symbolique préexistant déjà à l'intérieur de l'arborescence pourrait encore rediriger une écriture. Aussi, au moment de l'apply, `contained()` résout le chemin cible réel et confirme qu'il se situe sous la base du module, échouant en mode fermé lorsqu'il ne peut pas résoudre. Les écritures sont atomiques (écrire vers un nom temporaire, puis `rename` par-dessus la cible) et chaque écrasement est d'abord sauvegardé vers `rollback/` ; une sauvegarde en échec interrompt l'apply au lieu d'écraser sans filet de sécurité.

---

## Les deux profils

VDLU s'exécute dans l'un de deux profils de confiance, défini par `profile=` dans la config.

### `hardened` (le défaut public)

- **La signature est obligatoire.** Le manifeste doit porter une signature ed25519 valide d'une clé du keyring sur l'appareil, sinon la transaction est interrompue.
- **Le downgrade est bloqué.** Un manifeste dont la `version` est inférieure à la version installée est refusé. Un attaquant ne peut pas vous ramener à un build connu comme vulnérable.
- C'est le profil pour tout module distribué au public via `https://`.

### `trusted` (source privée, par SSH)

- La vérification de signature est au **mieux (best-effort)** : la source est un feed privé `file://` ou par SSH que vous contrôlez, aussi une signature manquante ou non vérifiable n'interrompt pas durement.
- **Mais le `sha256` de chaque blob est toujours vérifié, systématiquement.** `trusted` relâche *qui a signé le manifeste*, jamais *si les octets correspondent au plan*. L'intégrité du contenu est non négociable dans les deux profils.

---

## Fail-closed par inversion

C'est la partie subtile, et c'est la partie que la plupart des systèmes ratent.

`trusted` est la **seule** chaîne qui opte pour la vérification relâchée. Le moteur ne teste pas "est-ce `hardened` ?" Il teste "est-ce **pas** `trusted` ?" :

```sh
prof=$(cfg profile hardened | tr -d '[:space:]')
...
if [ "$prof" != trusted ]; then
    # signature mandatory
fi
```

Ainsi **tout** autre que le littéral `trusted` se résout en comportement hardened :

- la ligne manque entièrement -> hardened
- une faute de frappe comme `hardend` -> hardened
- `trusted ` avec un espace final, ou un `\r` issu de CRLF -> hardened
- `Trusted` avec une mauvaise casse -> hardened
- une valeur malmenée par un MITM -> hardened

Une version antérieure mettait par défaut une ligne *manquante* à hardened, ce qui laissait encore une *valeur* corrompue retomber vers le chemin ouvert. C'était un fail-open : une chaîne de profil malmenée pouvait accepter silencieusement un manifeste non signé, et un manifeste non signé signifie un `.so` fourni par l'attaquant échangé sous MITM, ce qui est une exécution de code à distance au niveau root. L'inversion la ferme. La seule façon d'obtenir la vérification relâchée est d'écrire `trusted` exactement, et même alors les hachages des blobs sont vérifiés. Le moteur n'est jamais à une faute de frappe près d'accepter du code non signé. (Le `tr -d` enlève les espaces parasites afin qu'un `trusted` légitime avec un espacement négligé ne soit pas rejeté à tort, sans rouvrir la faille.)

**Ce test est porteur. Il doit rester `!= trusted` et ne jamais devenir `== hardened`.**

---

## Le manifeste est lié au module

Une seule clé de release signe de nombreux modules. Ainsi un manifeste valablement signé, pour un module *différent*, pourrait en principe être servi à celui-ci (une mauvaise configuration du feed, un échange de source, ou une redirection MITM) et sa signature se vérifierait.

VDLU ferme cela avec une liaison : le champ signé `module` à l'intérieur du manifeste doit égaler le `MODID` de cette installation, sinon le manifeste est rejeté comme un feed inter-modules. Parce que `module` est à l'intérieur de la forme canonique signée, un attaquant ne peut pas le changer sans casser la signature. Un feed valablement signé pour le module B ne peut tout simplement pas être appliqué au module A.

---

## Le vérificateur mince sur l'appareil

La vérification sur l'appareil utilise **ed25519-mini**, un minuscule vérificateur en vérification-seule bâti sur TweetNaCl (domaine public). Il n'y a **pas d'`openssl` sur l'appareil**.

- L'entrée du keyring est la **clé publique de 32 octets bruts**, stockée comme `keyring/<key_id>.pub`. (La clé publique PEM est un artefact côté PC uniquement ; copier un PEM dans le keyring de l'appareil casse la vérification, car le vérificateur attend exactement 32 octets bruts.)
- `vdlu-verify <manifest.json> <keyring_dir>` reconstruit la forme canonique (le texte du manifeste avec le champ `sig` retiré, compact, clés triées), le hache vers le message hex de 64 caractères que la signature couvre, décode la signature base64, vérifie qu'elle fait 64 octets, et demande à `ed25519-mini <pub32> <msg> <sig64>` un verdict. rc 0 = valide, tout autre = rejet.
- Le binaire est statique par ABI (arm64-v8a, armeabi-v7a, x86, x86_64), avec un `PROVENANCE.json` qui épingle les sources TweetNaCl exactes, le hachage du wrapper et les drapeaux de build, de sorte que ce qui s'exécute en tant que root est auditable.
- Le `key_id` du manifeste est lui-même assaini (pas de `/`, pas de `..`, pas de guillemet) avant d'être utilisé pour choisir un fichier de keyring, de sorte qu'il ne peut pas s'échapper du répertoire du keyring.

### Le keyring est flash-only, vérifier-ne-pas-copier, stable

Le keyring est livré à l'intérieur du module au moment du flashage et n'est pas réécrit par le moteur de mise à jour. À la ré-intégration la règle est **vérifier, ne pas copier** : le keyring ne change que lors d'une rotation de clé délibérée, jamais comme effet de bord d'une mise à jour.

### La rotation de clé ne brique pas les anciennes installations

Lorsqu'une clé de signature est tournée, le keyring livre **à la fois la clé publique brute courante et la précédente**. Le vérificateur sélectionne le fichier de clé par le `key_id` du manifeste, de sorte qu'un feed encore signé par l'ancienne clé se vérifie contre l'ancienne pubkey, et un feed signé par la nouvelle clé se vérifie contre la nouvelle. Un appareil qui n'a pas mis à jour au-delà de la rotation continue de fonctionner ; rien n'est laissé en rade.

---

## La liste d'autorisation des `key_id` de mise à jour de module

La rotation de clé signifie déjà que le keyring peut légitimement contenir plus d'une clé, et un module peut en contenir plus d'une pour une seconde raison : il peut livrer une clé de moindre confiance qui signe un feed *différent*. Le feed de fingerprint est exactement ce cas. Un module peut porter une clé étroite dont le seul rôle est de signer un feed de fingerprint, logée dans le même keyring juste à côté de la clé de release qui signe le module lui-même.

Cela soulève une question à laquelle l'histoire de la rotation seule ne répond pas : une fois que deux clés vivent dans le keyring, *laquelle* d'entre elles est autorisée à signer une **mise à jour de module** ? Une mise à jour de module est la chose la plus puissante qu'un manifeste puisse demander, car elle réécrit des fichiers que l'appareil exécute en tant que root. Le vérificateur choisissait autrefois la clé publique nommée par le `key_id` du manifeste et acceptait n'importe quelle clé qui se trouvait présente dans le keyring. Ainsi la clé de moindre confiance du feed de fingerprint, si elle fuitait, pouvait signer un manifeste de mise à jour de module et l'appareil l'honorerait. C'est un contournement de la racine de confiance : une clé destinée à un rôle étroit pouvait piloter une mise à jour root complète sans flashage.

Le correctif épingle le `key_id` de mise à jour de module accepté à une **liste d'autorisation** fail-closed, vérifiée **avant** que la clé publique ne soit même sélectionnée. La clé de config est `key_id`, et le moteur la résout ainsi :

- **Un keyring à clé unique épingle automatiquement cette seule clé.** Le cas courant n'a besoin d'aucune config : si le keyring contient exactement une clé, cette clé *est* la liste d'autorisation, et rien d'autre ne peut signer une mise à jour de module.
- **Un keyring à plusieurs clés doit définir `key_id`.** Dès qu'une seconde clé apparaît, le moteur refuse de deviner. Il échoue en mode fermé avec "multiple keys in keyring; config must pin key_id" jusqu'à ce que la config nomme la clé (ou les clés, séparées par des virgules pendant une fenêtre de rotation) qui peut signer les mises à jour de module.

Parce que la vérification s'exécute avant la sélection de la clé publique, un manifeste nommant une clé présente mais non autorisée est rejeté sans que le vérificateur ne charge jamais cette clé. L'ensemble résolu est répercuté dans `vdlu-verify` via `VDLU_KEYID_ALLOW`, de sorte que le vérificateur mince sur l'appareil applique le même épinglage et que les deux ne peuvent pas diverger. Cela vaut dans les **deux** profils : `hardened` et `trusted` consultent tous deux la liste d'autorisation, car la liste d'autorisation décide *quelle clé* est une racine valide de mise à jour de module, non pas *si* une signature est requise.

Le feed de fingerprint garde sa propre racine de confiance épinglée séparée, `FEED_KEY_ID`. C'est une racine distincte avec un rôle distinct, jamais atteignable par le chemin de mise à jour de module ci-dessus, de sorte qu'épingler la liste d'autorisation de mise à jour de module n'y touche pas et qu'une clé de feed fuitée ne peut toujours pas signer une mise à jour de module. Ce changement a fait passer `ENGINE_VERSION` à 4.

---

## Ce que le manifeste d'outils ferme

L'amorçage mince du fetch télécharge un `curl` statique à la première utilisation pour les modules qui ne livrent pas le leur. Parce que ce binaire s'exécute en tant que root, la signature de son propre manifeste (ed25519-mini) et son hachage sont **obligatoires dans tout profil**, y compris `trusted`, avant qu'il ne soit installé ou exécuté. La webview n'est que du transport ; la confiance vient de la vérification de signature et de hachage sur l'appareil, jamais du fait qu'un téléchargement a réussi.

---

## Ce qu'un attaquant NE PEUT PAS faire

Même en possédant le feed, ou en étant assis sur le fil comme un MITM complet, un attaquant ne peut pas :

- **Écrire hors du module.** Les chemins absolus, `..`, `.`, les caractères de contrôle et les slashes finaux sont tous rejetés avant tout apply, et la redirection par lien symbolique est de nouveau détectée au moment de l'apply.
- **Supprimer hors du module.** Les entrées de `delete[]` passent la même validation de chemin.
- **Injecter une commande.** Aucune valeur du manifeste n'est interpolée dans un shell ou `awk system()` ; `sha256` doit être hex pur de 64 sinon le manifeste entier est rejeté.
- **Livrer du code non signé à une installation publique.** `hardened` rend la signature obligatoire, et le profil est fail-closed par inversion, de sorte qu'aucune faute de frappe ou valeur malmenée ne dégrade cela.
- **Signer une mise à jour de module avec une clé de moindre confiance.** Le `key_id` de mise à jour de module est épinglé à une liste d'autorisation fail-closed, vérifiée avant que la clé publique ne soit sélectionnée, de sorte qu'une clé de feed de fingerprint fuitée partageant le keyring ne peut pas signer une mise à jour root complète.
- **Servir ici le feed signé d'un autre module.** Le champ signé `module` doit égaler ce `MODID`.
- **Vous ramener en arrière.** Le downgrade est bloqué dans `hardened`.
- **Corrompre un blob sans être détecté.** Chaque blob téléchargé est re-haché contre le `sha256` du manifeste dans les deux profils ; un désaccord après trois essais interrompt la phase sans rien appliquer.
- **Échanger un faux fetcher root.** Le `curl` amorcé est vérifié par signature et hachage avant d'être installé ou exécuté, dans chaque profil.
- **Appliquer à moitié une mise à jour corrompue.** La transaction n'atteint `DONE` que lorsqu'un re-hachage de tout correspond ; un apply en échec revient en arrière au lieu d'écraser sans sauvegarde.

---

Voir aussi : [[Feed Format]] pour le schéma du manifeste, [[Engine]] pour la transaction dans laquelle vivent ces vérifications, et [[Architecture]] pour la vue d'ensemble.
