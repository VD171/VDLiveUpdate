> **Languages:** [English](../WEBUI.md) · [العربية](../ar/WEBUI.md) · [Čeština](../cs/WEBUI.md) · [Deutsch](../de/WEBUI.md) · [Español](../es/WEBUI.md) · [فارسی](../fa/WEBUI.md) · [Français](../fr/WEBUI.md) · [हिन्दी](../hi/WEBUI.md) · [Bahasa Indonesia](../id/WEBUI.md) · [Italiano](../it/WEBUI.md) · [日本語](../ja/WEBUI.md) · [한국어](../ko/WEBUI.md) · [Nederlands](../nl/WEBUI.md) · [Polski](../pl/WEBUI.md) · Português · [Русский](../ru/WEBUI.md) · [Svenska](../sv/WEBUI.md) · [ไทย](../th/WEBUI.md) · [Türkçe](../tr/WEBUI.md) · [Українська](../uk/WEBUI.md) · [Tiếng Việt](../vi/WEBUI.md) · [中文](../zh/WEBUI.md)

---

# VDLU - Widget WebUI (atualização flashless)

A interface do VDLU (VD Live Update) para uma WebUI de root manager KernelSU/APatch. Vanilla JS, sem framework, sem
build, sem CDN. Drop-in: o `index.html` hospedeiro carrega os 2 arquivos e chama a API.

Convergência: `INTERFACES.md` §9 (WEBUI↔ENGINE), §4 (journal.json), §5 (config).

## Arquivos

| Arquivo | O quê |
|---|---|
| `vdlu.js` | o componente - expõe `window.VDLU` |
| `vdlu.css` | toast de progresso, banner de reboot, aba "Updates" (tema escuro, herda as variáveis do hospedeiro) |
| `demo.html` | página standalone com um `ksu.exec` mockado - abre num navegador, sem device |

## Integração no `index.html` hospedeiro

```html
<link rel="stylesheet" href="vdlu.css">
...
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,   // $MODULE_DIR
    vdluDir:   '/data/adb/' + MODID + '/vdlu',  // $VDLU_DIR  (Tier-2, fora do diretório do módulo)
    modid:     MODID,
    module:    'Demo',                     // nome mostrado no toast (default: modid)
    exec:   ex,          // (opcional) o wrapper ksu.exec do hospedeiro; ver abaixo
    toast:  toast,       // (opcional) o toast transiente do hospedeiro
    confirm: askConfirm  // (opcional) o modal de confirmação do hospedeiro
  });

  VDLU.onWebUIOpen();                          // no load: avalia journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // quando a aba "Updates" é aberta
</script>
```

### O que o hospedeiro precisa definir

- **`moduleDir`** = `$MODULE_DIR` (`/data/adb/modules/<modid>`), onde o engine é vendorizado
  (`vdlu/update.sh`).
- **`vdluDir`** = `$VDLU_DIR` (`/data/adb/<modid>/vdlu`), o estado Tier-2 (`journal.json`, `config`,
  `cancel`).
- **`modid`** = o id do módulo.

O widget monta o comando do engine já carregando o env do contrato (§1):
`VDLU_DIR=… MODULE_DIR=… MODID=… sh $MODULE_DIR/vdlu/update.sh <cmd>`. `run`/`resume` vão para o
**background** (`(… &)`), e o progresso é lido por um poll leve (~1s) de `cat $VDLU_DIR/journal.json`.

### `exec`/`toast`/`confirm` (opcionais)

Se omitidos, o widget usa os seus próprios:
- **`exec(cmd)`** deve retornar uma `Promise` que **resolve** com stdout (rc 0) e **rejeita** com stderr
  (rc≠0) - exatamente a assinatura do `ex()` do `webroot/index.html` do Demo. O fallback interno chama
  `ksu.exec(cmd, '{}', cb)` com o mesmo contrato.
- **`toast(msg)`** = uma notificação transiente curta (o fallback injeta seu próprio mini-toast).
- **`confirm(title,msg,ok,danger,fn)`** = um modal (hoje usado só pelo hospedeiro; o widget não exige
  confirmação em nenhum fluxo).

Passar os próprios do hospedeiro faz o widget conversar pela MESMA fila serializada e visuais que o resto da
WebUI.

## API pública (`window.VDLU`)

| Função | Faz |
|---|---|
| `init(opts)` | configura (ver acima). Retorna `window.VDLU`. |
| `onWebUIOpen()` | chame-o no load: mostra o banner se `reboot_pending`; oferece **Resume** se houver uma transação não-terminal; com `auto_on_webui_open=1` roda uma **auto-atualização QUIETA** (um `check()` silencioso primeiro; só dispara `run`+toast persistente se `update && fetch>0` - atualizado/à-frente = resultado inline no painel, zero toast). |
| `mountUpdatesPanel(el)` | renderiza a aba "Updates" dentro de `el` (id string ou elemento): **Check for update**, **Update now**, os toggles `auto_on_webui_open`/`auto_on_reboot`, os campos de boot-retry, o select de **Network** (`net_policy`: Wi-Fi+móvel / só-Wi-Fi / só-móvel) e os campos `source`/`channel`/`profile`. |
| `check()` | roda `update.sh check`; `Promise<{update,from,to,fetch,reboot}>`. |
| `startUpdate()` | dispara `run` no background + um toast de progresso com **Cancel**. |
| `cancel()` | cria `$VDLU_DIR/cancel` (o engine para no ponto seguro). |
| `resume()` | `update.sh resume` + toast (retoma a fase atual). |
| `refreshBanner()` | reavalia o banner persistente de pending-reboot. |

O toast (overlay de canto, não-bloqueante) e o banner (topo, persistente) são injetados pelo widget em
`document.body` - o hospedeiro não precisa de HTML para eles. A aba "Updates" é o único ponto que o hospedeiro aloca (um
`<div>` vazio).

### O fluxo de estados que o toast reflete (journal.json, §4)

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)`; `ERROR` a qualquer momento. O
toast mostra **uma barra + `phase done/total · current · bytes`**. Terminais:
- **`DONE`** → toast verde "v&lt;target&gt; aplicada".
- **`PENDING_REBOOT`** (ou `reboot_pending=true`) → toast verde + **banner persistente** "⚠️ Reinicie para
  ativar a nova `.so` (vX)".
- **`ERROR`** → toast vermelho com o motivo (`journal.error`/stderr). Nunca finge sucesso.
- **Cancelado** → "cancelado - N/M, retomável" + um botão **Resume**.

## Rodando o demo

Abra `demo.html` num navegador (`xdg-open webui/demo.html`). O `ksu.exec` mockado simula o `update.sh` e
o `journal.json` evoluindo; os botões alternam entre os cenários **LIVE→DONE**, **reboot_pending**, **erro no meio**
e **cancelável**. É o mesmo `vdlu.js`/`vdlu.css` que no device.

## i18n (idioma)

As strings do widget default para **inglês** (neutro para os módulos públicos multi-idioma). O hospedeiro sobrepõe
qualquer chave passando um map no `init`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- define window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- Um merge **parcial** é ok: uma chave faltando cai no default inglês.
- As chaves de phase/state são `ph_<phase>` / `st_<STATE>`; o resto é flat (`cancel`, `updateNow`, …).
- O map de chaves completo = o objeto `DEFAULT_I18N` em `vdlu.js` (também exposto como `VDLU.i18n`).
- Uma tradução pronta é fornecida como exemplo trabalhado: `i18n/pt-BR.js`. Novos idiomas = um
  arquivo `i18n/<lang>.js` no mesmo molde, ou o hospedeiro constrói o map a partir do seu próprio sistema de i18n.

## Fonte única (paridade entre módulos)

Estes `vdlu.js`/`vdlu.css` são a **cópia canônica**. Todo módulo que embarca o widget
**re-vendoriza** esta cópia byte-a-byte no seu `webroot/` - **nunca** edita
a sua própria in place. Uma feature nova do widget nasce aqui e flui para baixo por re-vendor; o inverso produz drift
silencioso (já aconteceu na prática: uma cópia vendorizada ficou para trás e estava sem `net_policy`, o toast
`DEFERRED` e os campos `boot_retry`).

Guardião: [`../tools/webui-parity.sh`](../../tools/webui-parity.sh) acha toda cópia na árvore de fonte e acusa
as que divergem da canônica (só `vdlu.js`/`vdlu.css`; o keyring é "verificar, não copiar").

```sh
tools/webui-parity.sh         # relatório; sai 1 se houver drift
tools/webui-parity.sh --fix   # re-vendoriza as divergentes a partir da canônica
```

> 🪤 O keyring (`keyring/<id>.pub` RAW 32B) e o engine (`vdlu/update.sh`) têm sua própria cadência de re-vendor;
> este guardião cobre **só o widget WebUI**.

<!-- doc-footer -->

---

> _Esta documentação foi gerada com o Claude (Anthropic) e é mantida por VD171. Correções e melhorias são bem-vindas; veja [CONTRIBUTING.md](CONTRIBUTING.md)._
