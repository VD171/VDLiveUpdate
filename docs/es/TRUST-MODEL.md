> **Languages:** [English](../TRUST-MODEL.md) · [العربية](../ar/TRUST-MODEL.md) · [Čeština](../cs/TRUST-MODEL.md) · [Deutsch](../de/TRUST-MODEL.md) · Español · [فارسی](../fa/TRUST-MODEL.md) · [Français](../fr/TRUST-MODEL.md) · [हिन्दी](../hi/TRUST-MODEL.md) · [Bahasa Indonesia](../id/TRUST-MODEL.md) · [Italiano](../it/TRUST-MODEL.md) · [日本語](../ja/TRUST-MODEL.md) · [한국어](../ko/TRUST-MODEL.md) · [Nederlands](../nl/TRUST-MODEL.md) · [Polski](../pl/TRUST-MODEL.md) · [Português](../pt/TRUST-MODEL.md) · [Русский](../ru/TRUST-MODEL.md) · [Svenska](../sv/TRUST-MODEL.md) · [ไทย](../th/TRUST-MODEL.md) · [Türkçe](../tr/TRUST-MODEL.md) · [Українська](../uk/TRUST-MODEL.md) · [Tiếng Việt](../vi/TRUST-MODEL.md) · [中文](../zh/TRUST-MODEL.md)

---

# Política de seguridad y modelo de confianza

VDLiveUpdate (VDLU) aplica **actualizaciones root flashless** a un módulo vivo: escribe
en `/data/adb/modules/<mod>` e intercambia un `.so` de Zygisk en el arranque. Cada campo de un
manifiesto obtenido (`path`, `sha256`, `delete[]`, `mode`, ...) es **entrada hostil** - un
feed envenenado o un MITM lo entrega. Esta página es el modelo de confianza y la política de
divulgación responsable. Para el contrato de costura completo ver [`INTERFACES.md`](INTERFACES.md),
y los internos de engine/producer en [`ENGINE.md`](ENGINE.md) y
[`PRODUCER.md`](PRODUCER.md), la página de wiki **Security-and-Trust-Model** lleva el
mismo modelo para lectores fuera del repo.

## Versiones soportadas

Las correcciones de seguridad llegan al último `ENGINE_VERSION`, un manifiesto firmado declara el
engine mínimo que necesita vía `engine_min`, y el engine en el dispositivo rechaza un manifiesto
que pida más de lo que implementa. Se espera que los engines vendorizados más antiguos hagan
**re-vendor** para recoger una corrección, no que se les parchee en el lugar.

| ENGINE_VERSION | estado |
|---|---|
| 7 (actual) | soportado - nunca revertir un módulo por delante del feed (el `versionCode` instalado en vivo fija el piso de la versión "from"), auto-reparación en el arranque de un plan de downgrade obsoleto |
| 6 | superado - auto-reparación en el arranque de un journal obsoleto con `target <= 0` (el baseline 0 de un stub eliminado ya no dispara ninguna UI ni acción de arranque) |
| 5 | superado - exclusión del ancla de confianza del lado del engine (el directorio `vdlu/` se ignora aunque un feed lo lleve), topes de 128 MiB por archivo / 2 MiB de manifiesto |
| 4 | superado - allowlist de `key_id`, rechazo de paths con dot-segment/trailing-slash, topes de tamaño, lock en check-time |
| <= 3 | sin soporte - re-vendorizar el engine actual |

Cualquier cambio en la verificación del engine o la lógica de apply sube `ENGINE_VERSION`.

## Reportar una vulnerabilidad

Reporta en privado. **No** abras un issue, PR o post de foro públicos por un bug de seguridad.
Usa los contactos del proyecto (ver [`CONTRIBUTING.md`](../CONTRIBUTING.md)):

- Telegram: **@VD_Priv8** (https://t.me/VD_Priv8)
- Canal: **@Priv8_VD** (https://t.me/Priv8_VD)
- E-mail: **vd.priv8@pm.me**

Por favor incluye la versión del engine, el `profile` en uso, y un manifiesto o feed que
reproduzca el problema. Las correcciones se publican como un nuevo `ENGINE_VERSION` con una entrada
en `CHANGELOG.md`, coordina el momento de la divulgación en el hilo del reporte.

## Modelo de confianza

- **Firmas ed25519 desacopladas.** El producer firma el manifiesto canónico en la
  PC (openssl), el dispositivo verifica con el `ed25519-mini` embebido - **sin openssl en
  el dispositivo**. El mensaje firmado es el sha256 hex del manifiesto sin su campo `sig`
  (claves ordenadas, compacto, UTF-8), así que firma y verify derivan los mismos bytes en dos
  runtimes sin una librería JSON en el dispositivo.
- **Keyring = pubkeys RAW de 32 bytes**, flash-only. El keyring del dispositivo entrega `<key_id>.pub`
  como la clave raw de 32 bytes (nunca el PEM), `vdlu-pack` **excluye** el keyring y los
  binarios de `verify/` del feed, así que un manifiesto nunca puede reescribir el ancla de confianza
  en el dispositivo por la red.
- **Exclusión del ancla de confianza del lado del engine (VDLU#2).** Independientemente de la
  exclusión del lado del producer de arriba, el engine en el dispositivo **ignora** cada path
  `vdlu/` (`update.sh`, `vdlu-verify`, `verify/*`, `keyring/*`, config) en un plan obtenido - nunca
  los obtiene, aplica, ni borra, aunque un feed los lleve. Un feed publicado entrega el árbol entero
  del módulo, `vdlu/` incluido, así que el engine descarta en silencio esos paths en vez de rechazar
  el manifiesto: el módulo igual se actualiza, y el ancla de confianza cambia solo a través de un
  re-flash firmado completo. Una sola clave de firma filtrada ya no puede intercambiar el verificador
  o la clave de firma por la red y persistir root.
- **Allowlist de `key_id` de module-update (fail-closed, antes de la selección de pubkey).** Un keyring
  puede legítimamente llevar más de una clave (por ejemplo una clave de fingerprint-feed de menor
  confianza junto a la clave de release). Antes de que `<key_id>.pub` se seleccione siquiera, `verify_manifest`
  rechaza cualquier manifiesto cuyo `key_id` no esté en la allowlist configurada, en **ambos**
  profiles, y refleja el conjunto resuelto hacia `vdlu-verify` vía `VDLU_KEYID_ALLOW`. Esto
  cierra un bypass donde una clave filtrada de menor confianza podría de otro modo firmar una
  actualización root flashless completa. Seguro por defecto cuando `key_id` no está definido: un keyring
  **de una clave** se auto-fija a esa única clave, un keyring **multiclave** se rechaza hasta que `key_id`
  esté fijado (separado por comas para rotación).
- **La raíz de confianza del fingerprint-feed es un path separado y fijado** con su propia clave, nunca
  es alcanzable a través del path de module-update de arriba.
- **El baseline es una semilla local confiable.** `baseline.json` llega dentro del zip flasheado -
  la frontera de confianza de la instalación - así que es sin firma y sin clave y **no** pasa por
  `vdlu-verify`, solo un manifiesto **obtenido** del feed se verifica. Esto mantiene la
  clave de firma fuera de la CI.

## Garantías fail-closed

- **`validate_plan` corre antes de cualquier fetch o apply.** En `do_diff`, fail-closed,
  rechaza el manifiesto **entero** si algún `path` es absoluto, contiene un segmento `..` o `.`,
  termina en `/`, o lleva un carácter de control, si algún `sha256` no es
  `^[0-9a-f]{64}$`, o si algún `mode`/`class`/`enc` es inválido. Ningún campo hostil alcanza
  un shell, y `cmd_check` no lleva ninguna interpolación `system()`.
- **Contención de path.** Cada escritura y borrado se confina a `MODULE_DIR` vía
  `contained()` - apply, delete, y el `stage_file` del reboot pasan todos la misma guarda.
  Los symlinks en el árbol los salta el producer (nunca filtran contenido de fuera de él).
- **Dos profiles, fail-closed por inversión.** `trusted` (fuente privada, staged por SSH) es
  el **único** opt-in a verify best-effort, **cualquier** otro valor - incluido un typo, un
  espacio/CR al final, o un caso distinto - se trata como `hardened`, donde una firma válida
  es **obligatoria** y un fallo aborta. El `sha256` de cada blob se verifica en
  ambos profiles.
- **Firma + hash antes de cualquier ejecución de herramienta.** El `curl` estático obtenido corre como root, así que
  `install-tool` verifica la firma del tools-manifest (ed25519-mini, obligatoria en **cualquier**
  profile) y el hash del curl **antes** de que se instale y ejecute - sig+hash antes del
  exec cierra el RCE.
- **Transacción retomable y segura ante pin.** El manifiesto en vuelo se fija en `target.json`;
  un crash, pérdida de red, o reboot se reanuda desde el journal sin re-decidir el plan.
  El downgrade está bloqueado (`version` monotónica), el campo `module` firmado debe igualar
  `MODID`, y `delete[]` corre solo en `finalize_done` (un `PENDING_REBOOT` no borra
  nada). Nada está jamás "hecho" sin un re-hash completo, nada se sobrescribe sin
  un backup `rollback/<v>/` primero.

## Endurecimiento (defensa en profundidad)

- **Topes de tamaño.** El manifiesto, el tools-manifest, y el path de descarga `wget`/`head -c`
  sin curl están todos acotados antes de leerse (anti-OOM / anti-flood). Un blob falla
  su fase tras 3 intentos. Los topes son **128 MiB por archivo** (`MAX_FILE_BYTES`) y **2 MiB para
  el manifiesto** (`MAX_MANIFEST_BYTES`), impuestos en `update.sh` y reflejados en `vdlu-verify`.
- **Lock en check-time.** `check` toma el mkdir-lock antes de reconstruir su directorio de trabajo, así que
  un run concurrente no puede correr una carrera contra él.
- **Contención del staging.** `stage_file` tiene la misma guarda `contained()` que las primitivas
  de apply vivo, así que un path reboot-hard staged tampoco puede escapar de `MODULE_DIR`.
- **El TLS es defensa en profundidad, no la raíz de confianza.** El curl estático usa mbedTLS con el
  trust store de Android (`--capath`, override `ca_path`), la garantía de integridad es la
  firma ed25519, el chequeo del cert es una segunda capa.

## Ver también

- [`INTERFACES.md`](INTERFACES.md) - el contrato de costura inmutable (§5 config, §6 firma, §11 toolchain).
- [`ENGINE.md`](ENGINE.md) - el engine del lado del dispositivo y su máquina de estados.
- [`PRODUCER.md`](PRODUCER.md) - packing, firma, canonicalización, y rotación de claves.
- Wiki: **Security-and-Trust-Model**.

<!-- doc-footer -->

---

> _Esta documentación se generó con Claude (Anthropic) y la mantiene VD171. Las correcciones y mejoras son bienvenidas, consulta [CONTRIBUTING.md](CONTRIBUTING.md)._
