> **Languages:** [English](../WEBUI.md) · [العربية](../ar/WEBUI.md) · [Čeština](../cs/WEBUI.md) · [Deutsch](../de/WEBUI.md) · Español · [فارسی](../fa/WEBUI.md) · [Français](../fr/WEBUI.md) · [हिन्दी](../hi/WEBUI.md) · [Bahasa Indonesia](../id/WEBUI.md) · [Italiano](../it/WEBUI.md) · [日本語](../ja/WEBUI.md) · [한국어](../ko/WEBUI.md) · [Nederlands](../nl/WEBUI.md) · [Polski](../pl/WEBUI.md) · [Português](../pt/WEBUI.md) · [Русский](../ru/WEBUI.md) · [Svenska](../sv/WEBUI.md) · [ไทย](../th/WEBUI.md) · [Türkçe](../tr/WEBUI.md) · [Українська](../uk/WEBUI.md) · [Tiếng Việt](../vi/WEBUI.md) · [中文](../zh/WEBUI.md)

---

# VDLU - Widget WebUI (actualización flashless)

La interfaz VDLU (VD Live Update) para una WebUI de root manager KernelSU/APatch. Vanilla JS, sin framework, sin
build, sin CDN. Drop-in: el `index.html` anfitrión carga los 2 archivos y llama a la API.

Convergencia: `INTERFACES.md` §9 (WEBUI↔ENGINE), §4 (journal.json), §5 (config).

## Archivos

| Archivo | Qué |
|---|---|
| `vdlu.js` | el componente - expone `window.VDLU` |
| `vdlu.css` | toast de progreso, banner de reboot, pestaña "Updates" (tema oscuro, hereda las variables del anfitrión) |
| `demo.html` | página standalone con un `ksu.exec` mockeado - abre en un navegador, sin dispositivo |

## Integración en el `index.html` anfitrión

```html
<link rel="stylesheet" href="vdlu.css">
...
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,   // $MODULE_DIR
    vdluDir:   '/data/adb/' + MODID + '/vdlu',  // $VDLU_DIR  (Tier-2, outside the module dir)
    modid:     MODID,
    module:    'Demo',                     // name shown in the toast (default: modid)
    exec:   ex,          // (optional) the host's ksu.exec wrapper; see below
    toast:  toast,       // (optional) the host's transient toast
    confirm: askConfirm  // (optional) the host's confirmation modal
  });

  VDLU.onWebUIOpen();                          // on load: evaluates journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // when the "Updates" tab is opened
</script>
```

### Lo que el anfitrión debe definir

- **`moduleDir`** = `$MODULE_DIR` (`/data/adb/modules/<modid>`), donde el engine está vendorizado
  (`vdlu/update.sh`).
- **`vdluDir`** = `$VDLU_DIR` (`/data/adb/<modid>/vdlu`), el estado Tier-2 (`journal.json`, `config`,
  `cancel`).
- **`modid`** = el id del módulo.

El widget ensambla el comando del engine ya cargando el env del contrato (§1):
`VDLU_DIR=… MODULE_DIR=… MODID=… sh $MODULE_DIR/vdlu/update.sh <cmd>`. `run`/`resume` van al
**fondo** (`(… &)`), y el progreso se lee por un poll ligero (~1s) de `cat $VDLU_DIR/journal.json`.

### `exec`/`toast`/`confirm` (opcionales)

Si se omiten, el widget usa los suyos:
- **`exec(cmd)`** debe devolver una `Promise` que **resuelve** con stdout (rc 0) y **rechaza** con stderr
  (rc≠0) - exactamente la firma del `ex()` del `webroot/index.html` de la Demo. El fallback interno llama a
  `ksu.exec(cmd, '{}', cb)` con el mismo contrato.
- **`toast(msg)`** = una notificación transitoria corta (el fallback inyecta su propio mini-toast).
- **`confirm(title,msg,ok,danger,fn)`** = un modal (hoy usado solo por el anfitrión; el widget no requiere
  confirmación en ningún flujo).

Pasar los propios del anfitrión hace que el widget hable a través de la MISMA cola serializada y los mismos
visuales que el resto de la WebUI.

## API pública (`window.VDLU`)

| Función | Hace |
|---|---|
| `init(opts)` | configura (ver arriba). Devuelve `window.VDLU`. |
| `onWebUIOpen()` | llámala al cargar: muestra el banner si `reboot_pending`; ofrece **Resume** si hay una transacción no terminal; con `auto_on_webui_open=1` corre una **auto-actualización SILENCIOSA** (un `check()` silencioso primero; solo dispara `run`+toast persistente si `update && fetch>0` - al día/por delante = resultado inline en el panel, cero toast). |
| `mountUpdatesPanel(el)` | renderiza la pestaña "Updates" dentro de `el` (id string o elemento): **Check for update**, **Update now**, los toggles `auto_on_webui_open`/`auto_on_reboot`, los campos de boot-retry, el select **Network** (`net_policy`: Wi-Fi+móvil / solo Wi-Fi / solo móvil) y los campos `source`/`channel`/`profile`. |
| `check()` | corre `update.sh check`; `Promise<{update,from,to,fetch,reboot}>`. |
| `startUpdate()` | dispara `run` en el fondo + un toast de progreso con **Cancel**. |
| `cancel()` | crea `$VDLU_DIR/cancel` (el engine para en el punto seguro). |
| `resume()` | `update.sh resume` + toast (retoma la fase actual). |
| `refreshBanner()` | re-evalúa el banner persistente de pending-reboot. |

El toast (overlay de esquina, no bloqueante) y el banner (arriba, persistente) son inyectados por el widget en
`document.body` - el anfitrión no necesita HTML para ellos. La pestaña "Updates" es el único punto que el
anfitrión asigna (un `<div>` vacío).

### El flujo de estados que el toast refleja (journal.json, §4)

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)`; `ERROR` en cualquier momento. El
toast muestra **una barra + `phase done/total · current · bytes`**. Terminales:
- **`DONE`** → toast verde "v&lt;target&gt; applied".
- **`PENDING_REBOOT`** (o `reboot_pending=true`) → toast verde + **banner persistente** "⚠️ Reboot to
  activate the new `.so` (vX)".
- **`ERROR`** → toast rojo con la razón (`journal.error`/stderr). Nunca finge éxito.
- **Cancelado** → "cancelled - N/M, resumable" + un botón **Resume**.

## Correr la demo

Abre `demo.html` en un navegador (`xdg-open webui/demo.html`). El `ksu.exec` mockeado simula `update.sh` y el
`journal.json` evolucionando; los botones alternan entre los escenarios **LIVE→DONE**, **reboot_pending**, **error
a mitad** y **cancelable**. Es el mismo `vdlu.js`/`vdlu.css` que en el dispositivo.

## i18n (idioma)

Las cadenas del widget usan por defecto **inglés** (neutral para los módulos públicos multiidioma). El anfitrión
sobrescribe cualquier clave pasando un map en `init`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- Un merge **parcial** está bien: una clave faltante cae al default en inglés.
- Las claves de phase/state son `ph_<phase>` / `st_<STATE>`; el resto es plano (`cancel`, `updateNow`, …).
- El map de claves completo = el objeto `DEFAULT_I18N` en `vdlu.js` (también expuesto como `VDLU.i18n`).
- Una traducción lista se provee como ejemplo trabajado: `i18n/pt-BR.js`. Nuevos idiomas = un archivo
  `i18n/<lang>.js` en el mismo molde, o el anfitrión construye el map desde su propio sistema i18n.

## Fuente única (paridad entre módulos)

Estos `vdlu.js`/`vdlu.css` son la **copia canónica**. Cada módulo que embebe el widget
**re-vendoriza** esta copia byte a byte en su `webroot/` - **nunca** edita
la suya in place. Una nueva función del widget nace aquí y fluye hacia abajo por re-vendor; lo inverso produce
drift silencioso (ha pasado en la práctica: una copia vendorizada se quedó atrás y le faltaban `net_policy`, el
toast `DEFERRED` y los campos `boot_retry`).

Guardián: [`../tools/webui-parity.sh`](../../tools/webui-parity.sh) encuentra cada copia en el árbol fuente y acusa
a las que divergen de la canónica (solo `vdlu.js`/`vdlu.css`; el keyring es "verificar, no copiar").

```sh
tools/webui-parity.sh         # report; exits 1 if there is drift
tools/webui-parity.sh --fix   # re-vendors the divergent ones from the canonical
```

> 🪤 El keyring (`keyring/<id>.pub` RAW 32B) y el engine (`vdlu/update.sh`) tienen su propia cadencia de
> re-vendor; este guardián cubre **solo el widget WebUI**.

<!-- doc-footer -->

---

> _Esta documentación se generó con Claude (Anthropic) y la mantiene VD171. Las correcciones y mejoras son bienvenidas; consulta [CONTRIBUTING.md](CONTRIBUTING.md)._
