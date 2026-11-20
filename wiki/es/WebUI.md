# WebUI

VDLU incluye un widget WebUI opcional de inserción directa: un pequeño panel "Updates" para una WebUI de gestor de root de KernelSU o APatch. Le da al usuario un botón Check, un botón Update now, un toast de progreso en vivo con cancelación, un banner de reinicio y un panel de ajustes, todo sin que el usuario toque jamás una terminal.

Es **JavaScript plano**: sin framework, sin paso de build, sin CDN. Tres archivos:

| Archivo | Qué es |
|---|---|
| `vdlu.js` | el widget; expone `window.VDLU` |
| `vdlu.css` | los estilos para el toast, el banner y el panel (tema oscuro, hereda las variables CSS del anfitrión) |
| `demo.html` | una página autónoma que simula el puente del dispositivo, de modo que toda la UI corre en un navegador normal |

El widget es enteramente opcional. El [[Engine]] corre bien por sí solo desde los disparadores de arranque; la WebUI es solo una cara amigable encima de él. Ver [[Quick Start]] para conectarlo en un módulo.

---

## Cómo la UI habla con el motor: el puente `ksu.exec`

El widget nunca hace nada privilegiado por sí mismo. Construye un comando de shell y lo entrega al puente `ksu.exec` del gestor de root, que lo ejecuta como root y devuelve stdout / stderr / código de salida. Todo lo que el panel muestra se lee de vuelta de archivos que el motor escribe.

El widget envuelve ese puente en una única función `exec(cmd)` que devuelve una `Promise`:

- **se resuelve** con stdout cuando el comando sale con 0
- **se rechaza** con stderr (o `rc=N`) en caso contrario

Cada comando lleva el entorno del contrato, ensamblado por el widget:

```
VDLU_DIR=... MODULE_DIR=... MODID=... sh $MODULE_DIR/vdlu/update.sh <cmd>
```

Unas pocas llamadas concretas:

- **Iniciar una actualización:** `update.sh run` se lanza en **segundo plano** (`(... &)`) para que la UI nunca quede bloqueada por una descarga larga.
- **Leer el progreso:** un sondeo ligero (alrededor de una vez por segundo) de `cat $VDLU_DIR/journal.json`.
- **Cancelar:** `touch $VDLU_DIR/cancel` (el motor se detiene en el siguiente punto seguro).
- **Config:** leer y escribir `$VDLU_DIR/config` (clave=valor), preservando el orden y las claves desconocidas y tocando solo las claves que el usuario cambió.

Si el anfitrión pasa sus propios ayudantes `exec`, `toast` y `confirm` a `init()`, el widget se enruta a través de la propia cola de comandos serializada y los visuales del anfitrión, de modo que luce y se comporta como el resto de esa WebUI. Si se omiten, el widget recurre a llamar `ksu.exec` directamente e inyecta su propio mini-toast.

---

## El toast de progreso (con cancelación)

Una vez que una actualización está corriendo, el widget muestra un toast no bloqueante en la esquina y sondea `journal.json`. El toast refleja la máquina de estados del motor:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

Renderiza una barra de progreso más una línea de `phase done/total - current file - bytes`, y lleva un botón **Cancel** en todo momento. Los estados terminales reciben cada uno su propio tratamiento:

- **DONE** -> un toast verde, "vX applied - all verified".
- **PENDING_REBOOT** -> un toast verde más un banner de reinicio persistente (abajo).
- **ERROR** -> un toast rojo con la razón de `journal.error` o stderr, ofreciendo Retry. Nunca finge éxito.
- **Cancelled** -> un toast ámbar, "cancelled - N/M applied, resumable", ofreciendo **Resume**.
- **DEFERRED** -> un toast informativo azul suave, "download deferred, waiting for the allowed network". Esta es una espera benigna de política de red, no un error; se reanuda en el siguiente check o arranque en la red correcta.

El sondeo es defensivo. Un diario a medio escribir (el motor escribe de forma concurrente) se ignora en ese tick en vez de malinterpretarlo. Si el diario desaparece después de que se vio progreso, eso significa que el commit lo limpió: el widget reporta DONE. Si el diario está ausente desde el inicio durante 8 ticks, reporta "no response". Y si el diario se congela en los mismos valores durante 20 ticks, el widget comprueba el `lock.d` del motor: si el lock está vivo es solo un fetch lento de un único blob y el toast sigue esperando; si el lock está muerto la ejecución murió a mitad de camino, así que el widget muestra un error con un botón Resume en vez de girar en "updating" para siempre.

---

## El banner de reinicio

Algunos archivos no se pueden intercambiar en un sistema en vivo: un `.so`, un overlay de `/system`, un `sepolicy.rule`. El motor prepara esos por etapas y marca la transacción como `PENDING_REBOOT`. El widget muestra entonces un **banner superior persistente**: "Reboot to activate the new `.so` (vX)". Permanece hasta que los archivos por etapas se intercambien en el siguiente arranque. Al abrir la WebUI el banner se reevalúa desde el diario, de modo que un usuario que cierra y reabre la UI aún lo ve. Ver [[Reboot Handling]] para lo que sucede en el arranque.

Nota que el banner se activa por el estado terminal `PENDING_REBOOT`, no por la bandera `reboot_pending` (que se pone en true tan pronto como cualquier `.so` entra en el plan). Eso evita que el banner aparezca a mitad de ejecución antes de que nada esté realmente por etapas.

---

## El panel "Updates": alternadores independientes por categoría

`mountUpdatesPanel(el)` renderiza el panel de ajustes dentro de un `<div>` vacío que el anfitrión provee. Tiene tres secciones, y cada control es independiente y se guarda por su cuenta:

**Actions**
- **Check for updates** -> ejecuta `check`, muestra el resultado en línea (al día / más nuevo que el feed / actualización disponible con conteo de archivos y una etiqueta de reinicio).
- **Update now** -> dispara `run` más el toast de progreso.

**Automation** (alternadores independientes, cada uno escrito en `config` en el momento en que se cambia)
- **On WebUI open** (`auto_on_webui_open`) -> ejecutar una actualización silenciosa cuando se abre la UI.
- **On reboot** (`auto_on_reboot`) -> aplicar en pre-zygote en el arranque.
- **Boot retry every (s)** y **Boot retry up to (min)** -> campos numéricos para reintentar un fetch de manifiesto cuando el dispositivo arranca sin conexión.

**Source**
- `source` (la URL del feed), `channel` (stable / canary), `profile` (trusted / hardened), y un selector **Network** que mapea a `net_policy` (Wi-Fi + móvil / solo Wi-Fi / solo móvil).

Los alternadores y los campos numéricos se guardan de inmediato y revierten visualmente si la escritura falla. Los campos de texto y de selección en la sección Source se marcan como modificados y se guardan juntos con un botón Save explícito. El panel solo reescribe las claves que el usuario tocó, de modo que cualquier clave de config desconocida o futura se preserva.

### Comportamiento de auto-apertura

`onWebUIOpen()` se llama al cargar el anfitrión. Evalúa el diario (mostrando el banner de reinicio u ofreciendo Resume para una transacción no terminal dejada por una sesión previa), luego, si `auto_on_webui_open=1`, ejecuta primero un `check()` **silencioso**. El toast de progreso persistente y el `run` real solo se disparan cuando hay una descarga real que hacer (`update && fetch > 0`). Si el dispositivo está al día o por delante del feed, el resultado se muestra en línea en el panel y no queda ningún toast en pantalla, de modo que la autoactualización es tan poco intrusiva como el botón manual.

---

## i18n (cadenas por idioma)

Cada cadena de la UI tiene por defecto **inglés**, que es la elección neutral para módulos públicos multilingües. El mapa completo de claves vive en el objeto `DEFAULT_I18N` en `vdlu.js` (también expuesto como `VDLU.i18n`). Un anfitrión sobrescribe cualquier subconjunto de claves pasando un mapa a `init({ i18n: ... })`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>
  VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x',
              i18n: window.VDLU_I18N_PT_BR });
</script>
```

- Un mapa **parcial** está bien: cualquier clave faltante recae en el valor por defecto en inglés.
- Las etiquetas de fase y estado usan las claves `ph_<phase>` y `st_<STATE>`; el resto son claves planas como `cancel`, `updateNow`.
- Una traducción trabajada (`i18n/pt-BR.js`) se incluye como plantilla; un idioma nuevo es simplemente un archivo `i18n/<lang>.js` con la misma forma, o el anfitrión construye el mapa desde su propio sistema de i18n.

---

## demo.html: correr la UI sin dispositivo

`demo.html` simula el puente `ksu.exec` para que exactamente los mismos `vdlu.js` y `vdlu.css` corran en un navegador normal, sin root y sin teléfono:

```sh
xdg-open webui/demo.html
```

El simulacro imita `update.sh` y un `journal.json` en evolución, y sus botones alternan entre los escenarios: una actualización en vivo hasta DONE, un final `reboot_pending`, un error a mitad de camino y una ejecución cancelable. Es la forma más rápida de ver e iterar sobre la UI, y es lo que compruebas antes de incorporar el widget a un módulo.

---

## Conectándolo a un módulo (el disparador de apertura de WebUI)

El `index.html` del anfitrión carga los dos archivos y llama a tres funciones:

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

El anfitrión solo necesita suministrar las rutas Tier-2 y asignar un `<div>` vacío para el panel; el toast y el banner son inyectados en `document.body` por el widget. `onWebUIOpen()` es el disparador de apertura de WebUI: es lo que evalúa el banner de reinicio, ofrece Resume en una transacción interrumpida, y ejecuta la autoactualización silenciosa cuando `auto_on_webui_open` está activado.

### Fuente única, re-incorporada byte a byte

`vdlu.js` y `vdlu.css` son la **copia canónica**. Un módulo que embebe el widget re-incorpora estos archivos sin cambios en su `webroot/`; nunca edita su propia copia en su sitio. Una función nueva nace en los archivos canónicos y fluye hacia abajo por re-incorporación. Editar una copia incorporada produce una deriva silenciosa (ha pasado: a una copia obsoleta le faltaba `net_policy`, el toast DEFERRED y los campos de reintento de arranque). Un guardián de paridad en el árbol de fuente encuentra cada copia y marca o re-incorpora las que divergen, cubriendo solo el widget; el keyring tiene su propia cadencia de verificar-no-copiar.

---

### API pública (`window.VDLU`)

| Función | Hace |
|---|---|
| `init(opts)` | configura el widget; devuelve `window.VDLU` |
| `onWebUIOpen()` | llamar al cargar: banner, oferta de Resume y autoactualización silenciosa |
| `mountUpdatesPanel(el)` | renderiza el panel de Updates dentro de `el` (cadena id o elemento) |
| `check()` | ejecuta `update.sh check`; `Promise<{update, from, to, fetch, reboot}>` |
| `startUpdate()` | dispara `run` en segundo plano más el toast de progreso con Cancel |
| `cancel()` | crea `$VDLU_DIR/cancel` (el motor se detiene en un punto seguro) |
| `resume()` | reanuda la transacción actual más un toast |
| `refreshBanner()` | reevalúa el banner persistente de reinicio pendiente |

---

Ver también: [[Engine]] para los comandos que el widget maneja, [[Quick Start]] para los pasos completos de adopción, y [[Reboot Handling]] para lo que el banner está esperando.
