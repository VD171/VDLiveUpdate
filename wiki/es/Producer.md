# Producer

El **productor** es el lado de la PC / publicación de VDLU: el pequeño conjunto de herramientas que convierten un árbol de módulo terminado en un feed firmado y direccionado por contenido desde el cual el dispositivo puede actualizarse. Nada de esto corre en el teléfono. Estas herramientas corren en tu máquina de publicación (o, para las partes que es seguro, en CI).

Son cuatro:

| Herramienta | Corre en | Lenguaje | Trabajo |
|---|---|---|---|
| `vdlu-pack` | PC / CI | python3 | Recorrer el árbol final del módulo hacia `manifest.json` + `blobs/<sha256>` |
| `vdlu-keygen` | PC | sh + openssl | Generar un par de claves de firma ed25519 |
| `vdlu-sign` | PC | sh + openssl | Inyectar `key_id` + firma en un manifiesto, en su sitio |
| `vdlu-gc` | PC | python3 | Podar blobs huérfanos de un feed publicado (a prueba de fallos) |

El flujo de publicación es de tres pasos, hecho una vez por release: **empaquetar, luego firmar, luego publicar**. `vdlu-keygen` es una configuración de una sola vez, y `vdlu-gc` es mantenimiento que ejecutas cuando el feed crece. Todo lo que el productor emite se ajusta al [[Feed Format]], que es lo que el motor del dispositivo consume.

---

## vdlu-pack

`vdlu-pack` toma el **árbol exacto que envía tu `.zip`** (el árbol final, después de que tu build aplicó su propia lista blanca y el podado de ABI) y produce el feed para él.

```sh
vdlu-pack <module_tree_dir> <out_dir> <module_id> <version> \
          [--version-name v106] [--channel stable] [--prev ./prev/manifest.json]
```

Escribe dos cosas en `<out_dir>`:

- `manifest.json` - la descripción completa del árbol de destino (cada archivo con su `sha256`, `size`, `mode`, codificación y clase de reinicio), todavía **sin firmar** (los campos `key_id` y `sig` son marcadores de posición vacíos).
- `blobs/<sha256>` (o `blobs/<sha256>.gz`) - un blob por cada contenido de archivo distinto.

### Direccionado por contenido y deduplicante

Cada blob se nombra por el **sha256 de su contenido original (sin comprimir)**. Como el nombre es el hash, el contenido idéntico aterriza en el mismo blob. `vdlu-pack` escribe un blob solo si no está ya presente, así que:

- Un archivo que no cambió conserva el mismo nombre de blob, y nunca se reescribe ni se vuelve a subir.
- Dos archivos distintos con contenido idéntico comparten un blob.
- Un archivo revertido reutiliza el blob que ya estaba allí desde antes.

Por lo tanto, publicar es **incremental por construcción**: a través de las versiones, `blobs/` solo crece, y solo se agrega contenido genuinamente nuevo. El dispositivo descarga por los mismos hashes, así que solo baja los blobs que aún no tiene.

### Compresión (el campo `enc`)

Para cada archivo, `vdlu-pack` decide cómo almacenar el blob:

- `gz` cuando el archivo tiene al menos 4096 bytes **y** gzip (determinista `-9 -n`) ahorra al menos un 10 por ciento.
- `raw` en caso contrario (archivos pequeños que el gzip sobre la línea ya cubre, o datos ya incompresibles).
- Si falta `gzip` en el host de build, todo se almacena como `raw`. El empaquetado nunca falla por esto.

El `sha256` en el manifiesto es **siempre** del contenido original; `enc` solo nombra cómo se almacena el blob. El dispositivo descomprime los blobs `gz` con el `gunzip` de toybox y luego comprueba el hash contra el original.

### Clase de reinicio y seguridad

`vdlu-pack` también etiqueta cada archivo con una `class` de reinicio (`live`, `soft`, `reboot`) derivada de su ruta, para que el motor sepa qué se puede aplicar sin un reinicio y qué debe prepararse por etapas. Las reglas y lo que el dispositivo hace con cada clase se cubren en [[Reboot Handling]].

Unas pocas cosas que `vdlu-pack` deliberadamente **no** hace:

- No sigue enlaces simbólicos (los omite con una advertencia, de modo que contenido de fuera del árbol, como un enlace a un archivo del sistema, nunca pueda filtrarse a un blob).
- Omite archivos no regulares (directorios, fifos, dispositivos).
- Respeta `SOURCE_DATE_EPOCH` para la marca de tiempo `built`, de modo que los manifiestos sean reproducibles.
- Excluye por completo del feed un conjunto fijo de rutas (la raíz de confianza, el andamiaje del instalador y algunas otras). La lista completa, y por qué se excluye cada una, está en [[Feed Format]].

### La lista `delete[]`

Pasa `--prev <manifest.json previo>` y `vdlu-pack` calcula `delete[]`: las rutas que existían en la release anterior pero ya no están en esta, para que el dispositivo las elimine en vez de dejar huérfanos detrás. Las rutas excluidas nunca se emiten como eliminaciones, aun cuando aparezcan en el manifiesto anterior (ver [[Feed Format]] para la semántica exacta).

---

## vdlu-keygen

Un paso de una sola vez. `vdlu-keygen` crea el par de claves de firma ed25519 para tu feed.

```sh
vdlu-keygen <id> <out_dir>
```

Escribe tres archivos:

| Archivo | Qué es | A dónde va |
|---|---|---|
| `<id>.pem` | La clave de firma **privada** (mode `0600`) | Se queda en tu máquina de publicación. Nunca. |
| `<id>.pub` | La clave pública como PEM | Solo herramientas del lado PC |
| `<id>.pub.raw` | La clave pública como **32 bytes en crudo** | Enviada como la entrada del keyring en el dispositivo del módulo |

La clave pública de 32 bytes en crudo es lo que el verificador del dispositivo lee (no lleva `openssl`, así que no puede leer el PEM). Embebes `<id>.pub.raw` en el módulo como `vdlu/keyring/<id>.pub`. El PEM es solo para uso del lado PC. Esta división, y cómo funciona la rotación de claves, se explica en [[Security and Trust Model]].

> **Un keyring de varias claves debe fijar `key_id`.** Si el keyring del módulo envía más de una clave (por ejemplo la clave de release más una clave de feed de fingerprint de menor confianza), el motor no adivinará cuál puede firmar una actualización de módulo. Establece la configuración `key_id` en la clave, o las claves separadas por comas durante una ventana de rotación, que está permitida para firmar actualizaciones; un keyring de una sola clave fija automáticamente y no necesita configuración. Esta es la allowlist de actualización de módulo, cubierta en [[Security and Trust Model]].

> El `.pem` privado es el único secreto en todo el sistema. Mantenlo fuera de todo dispositivo y fuera de todo push a repositorio. Ver la nota de CI abajo.

---

## vdlu-sign

`vdlu-sign` toma el manifiesto sin firmar que produjo `vdlu-pack` y lo firma **en su sitio**.

```sh
vdlu-sign <manifest.json> <privkey.pem> <key_id>
```

Establece el campo `key_id`, calcula la forma canónica del manifiesto, y escribe la firma ed25519 (base64) en el campo `sig`. La firma es sobre una transformación de bytes precisa del manifiesto, de modo que la PC y el dispositivo deriven exactamente los mismos bytes firmados sin ninguna librería JSON en el dispositivo. Esa transformación (la **canonicalización**) es la invariante más importante del formato, y está documentada en su totalidad en [[Feed Format]].

La clave privada se lee solo aquí, en tu máquina, y nunca la abandona.

### La clave de firma se mantiene fuera de CI

Este es un punto de diseño deliberado. CI puede ejecutar `vdlu-pack` y producir una **baseline sin clave** perfectamente válida (un manifiesto semilla sin firmar; ver [[Feed Format]]), de modo que una instalación nueva nace al día sin que CI toque jamás una clave privada. La firma real del feed publicado la haces tú, localmente, con `vdlu-sign`. De esa manera la clave de firma está 100 por ciento fuera de CI, y solo el feed que publicas a mano está firmado.

---

## vdlu-gc

Como los blobs son direccionados por contenido e inmutables, `blobs/` solo crece: `vdlu-pack` agrega, nunca quita. A lo largo de muchas releases el feed (y el sitio de Pages que lo aloja) acumula blobs que ningún manifiesto actual referencia ya. `vdlu-gc` poda esos huérfanos.

```sh
vdlu-gc <feed_dir> [--keep-last N] [--keep extra.json ...] [--apply]
```

Construye el **conjunto retenido** de manifiestos: el `manifest.json` actual, más los últimos `N` manifiestos archivados por versión (por defecto `N=3`, dando un margen de rollback), más cualquiera que nombres con `--keep`. Un blob referenciado por **ningún** manifiesto retenido es un huérfano y es candidato a eliminación. El conjunto retenido es una unión, así que un blob permanece mientras alguna release retenida aún lo necesite; un dispositivo asentado en una versión retenida más antigua nunca pierde su fetch.

`vdlu-gc` está construido para ser seguro:

- **Dry-run por defecto.** Sin `--apply`, solo imprime lo que *eliminaría*. Agregas `--apply` para borrar de verdad.
- **A prueba de fallos.** Si no encuentra ningún manifiesto retenido, se niega a podar en vez de arriesgar vaciar un feed.
- **Retención por referencia, no por fecha.** Un blob se conserva porque un manifiesto retenido apunta a él, nunca por una marca de tiempo.

Después de podar, sube el feed más pequeño a tu host. Espacia la escritura si tu host limita la tasa de escrituras por lotes.

---

## Poniéndolo todo junto

Una release típica, de principio a fin:

```sh
# una sola vez: crear una clave de firma. Manten el .pem fuera de todo dispositivo y de todo push a repo.
vdlu-keygen release-2026 ./keys

# cada release: empaquetar el arbol final enviado (post-lista-blanca, el mismo arbol que envia el .zip)
vdlu-pack ./module_tree ./out demo 106 --version-name v106 --channel stable \
          --prev ./prev/manifest.json

# firmar el manifiesto en su sitio (local, la clave privada nunca abandona tu maquina)
vdlu-sign ./out/manifest.json ./keys/release-2026.pem release-2026

# publicar ./out/{manifest.json,blobs/} a tu source (GitHub Pages, rsync, ...).
# ocasionalmente: podar blobs huerfanos
vdlu-gc ./feed --keep-last 3            # dry-run primero
vdlu-gc ./feed --keep-last 3 --apply    # luego eliminar
```

Para el ejemplo completo y trabajado de adoptar VDLU en un módulo, ver [[Quick Start]]. Para la forma sobre la línea de todo lo que el productor emite, ver [[Feed Format]]. Para el razonamiento detrás del manejo de claves y lo que se mantiene fuera del feed, ver [[Security and Trust Model]].
