# WebUI

O VDLU inclui um widget de WebUI opcional e drop-in: um pequeno painel "Updates" para uma WebUI de root manager KernelSU ou APatch. Ele dá ao usuário um botão Check, um botão Update now, um toast de progresso ao vivo com cancelamento, um banner de reinício e um painel de configurações, tudo sem o usuário jamais tocar em um terminal.

Ele é **JavaScript vanilla**: sem framework, sem passo de build, sem CDN. Três arquivos:

| Arquivo | O que é |
|---|---|
| `vdlu.js` | o widget; expõe `window.VDLU` |
| `vdlu.css` | os estilos para o toast, o banner e o painel (tema escuro, herda as variáveis CSS do host) |
| `demo.html` | uma página standalone que mocka a ponte do dispositivo para que toda a UI rode em um navegador comum |

O widget é inteiramente opcional. O [[Engine]] roda bem por conta própria a partir de gatilhos de boot; a WebUI é apenas uma face amigável em cima dele. Veja [[Quick Start]] para ligá-lo a um módulo.

---

## Como a UI fala com o motor: a ponte `ksu.exec`

O widget nunca faz nada privilegiado por si mesmo. Ele monta um comando de shell e o entrega à ponte `ksu.exec` do root manager, que o roda como root e retorna stdout / stderr / código de saída. Tudo que o painel mostra é lido de volta de arquivos que o motor grava.

O widget envolve essa ponte em uma única função `exec(cmd)` que retorna uma `Promise`:

- **resolve** com stdout quando o comando sai com 0
- **rejeita** com stderr (ou `rc=N`) caso contrário

Todo comando carrega o ambiente do contrato, montado pelo widget:

```
VDLU_DIR=... MODULE_DIR=... MODID=... sh $MODULE_DIR/vdlu/update.sh <cmd>
```

Algumas chamadas concretas:

- **Iniciar uma atualização:** `update.sh run` é lançado em **segundo plano** (`(... &)`) para que a UI nunca seja bloqueada por um download longo.
- **Ler progresso:** um poll leve (cerca de uma vez por segundo) de `cat $VDLU_DIR/journal.json`.
- **Cancelar:** `touch $VDLU_DIR/cancel` (o motor para no próximo ponto seguro).
- **Config:** lê e grava `$VDLU_DIR/config` (key=value), preservando a ordem e chaves desconhecidas e tocando apenas nas chaves que o usuário mudou.

Se o host passa seus próprios helpers `exec`, `toast` e `confirm` para `init()`, o widget roteia pela própria fila de comandos serializada e visuais do host, de modo que ele se parece e se comporta como o resto daquela WebUI. Se forem omitidos, o widget recai em chamar `ksu.exec` diretamente e injeta seu próprio mini-toast.

---

## O toast de progresso (com cancelamento)

Uma vez que uma atualização está rodando, o widget mostra um toast de canto não bloqueante e faz poll de `journal.json`. O toast reflete a máquina de estados do motor:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

Ele renderiza uma barra de progresso mais uma linha de `phase done/total - current file - bytes`, e carrega um botão **Cancel** o tempo todo. Os estados terminais recebem cada um seu próprio tratamento:

- **DONE** -> um toast verde, "vX applied - all verified".
- **PENDING_REBOOT** -> um toast verde mais um banner de reinício persistente (abaixo).
- **ERROR** -> um toast vermelho com a razão de `journal.error` ou do stderr, oferecendo Retry. Ele nunca finge sucesso.
- **Cancelled** -> um toast âmbar, "cancelled - N/M applied, resumable", oferecendo **Resume**.
- **DEFERRED** -> um toast azul de informação suave, "download deferred, waiting for the allowed network". Esta é uma espera benigna de política de rede, não um erro; ela resume no próximo check ou boot na rede certa.

O poll é defensivo. Um journal gravado pela metade (o motor grava concorrentemente) é ignorado naquele tick em vez de ser mal parseado. Se o journal fica ausente depois que progresso foi visto, isso significa que o commit o limpou: o widget reporta DONE. Se o journal está ausente desde o início por 8 ticks, ele reporta "no response". E se o journal congela nos mesmos valores por 20 ticks, o widget confere o `lock.d` do motor: se o lock está vivo e apenas um fetch lento de um único blob e o toast continua esperando; se o lock está morto a execução morreu no meio, então o widget expõe um erro com um botão Resume em vez de girar em "updating" para sempre.

---

## O banner de reinício

Alguns arquivos não podem ser trocados em um sistema ao vivo: um `.so`, um overlay de `/system`, um `sepolicy.rule`. O motor estagia esses e marca a transação como `PENDING_REBOOT`. O widget então mostra um **banner superior persistente**: "Reboot to activate the new `.so` (vX)". Ele fica até que os arquivos estagiados sejam trocados no próximo boot. Na abertura da WebUI o banner é reavaliado a partir do journal, então um usuário que fecha e reabre a UI ainda o vê. Veja [[Reboot Handling]] para o que acontece no boot.

Observe que o banner se baseia no estado terminal `PENDING_REBOOT`, não na flag `reboot_pending` (que vira verdadeira assim que qualquer `.so` entra no plano). Isso impede o banner de aparecer no meio da execução antes de qualquer coisa estar de fato estagiada.

---

## O painel "Updates": toggles independentes por categoria

`mountUpdatesPanel(el)` renderiza o painel de configurações em um `<div>` vazio que o host fornece. Ele tem três seções, e cada controle é independente e salva por conta própria:

**Actions**
- **Check for updates** -> roda `check`, mostra o resultado inline (atualizado / mais novo que o feed / atualização disponível com contagem de arquivos e uma tag de reboot).
- **Update now** -> dispara `run` mais o toast de progresso.

**Automation** (toggles independentes, cada um gravado em `config` no momento em que é acionado)
- **On WebUI open** (`auto_on_webui_open`) -> roda uma atualização silenciosa quando a UI abre.
- **On reboot** (`auto_on_reboot`) -> aplica em pré-zygote no boot.
- **Boot retry every (s)** e **Boot retry up to (min)** -> campos numéricos para retentar um fetch de manifesto quando o dispositivo boota offline.

**Source**
- `source` (a URL do feed), `channel` (stable / canary), `profile` (trusted / hardened) e um select **Network** mapeando para `net_policy` (Wi-Fi + mobile / Wi-Fi only / mobile only).

Toggles e campos numéricos salvam imediatamente e revertem visualmente se a gravação falha. Os campos de texto e select na seção Source se marcam como dirty e salvam juntos em um botão Save explícito. O painel só reescreve as chaves que o usuário tocou, então quaisquer chaves de config desconhecidas ou futuras são preservadas.

### Comportamento de auto-open

`onWebUIOpen()` é chamado no carregamento do host. Ele avalia o journal (mostrando o banner de reinício ou oferecendo Resume para uma transação não terminal deixada por uma sessão anterior), depois, se `auto_on_webui_open=1`, roda um `check()` **silencioso** primeiro. O toast de progresso persistente e o `run` de fato só disparam quando há um download real a fazer (`update && fetch > 0`). Se o dispositivo está atualizado ou adiante do feed, o resultado aparece inline no painel e nenhum toast fica na tela, de modo que a atualização automática é tão não intrusiva quanto o botão manual.

---

## i18n (strings por idioma)

Toda string de UI defaulta para **inglês**, que é a escolha neutra para módulos públicos multi-idioma. O mapa de chaves completo vive no objeto `DEFAULT_I18N` em `vdlu.js` (também exposto como `VDLU.i18n`). Um host sobrescreve qualquer subconjunto de chaves passando um mapa para `init({ i18n: ... })`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>
  VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x',
              i18n: window.VDLU_I18N_PT_BR });
</script>
```

- Um mapa **parcial** é aceitável: qualquer chave faltando recai no default em inglês.
- Labels de fase e estado usam as chaves `ph_<phase>` e `st_<STATE>`; o resto são chaves planas como `cancel`, `updateNow`.
- Uma tradução trabalhada (`i18n/pt-BR.js`) vem como um template; um novo idioma é apenas um arquivo `i18n/<lang>.js` no mesmo formato, ou o host monta o mapa a partir de seu próprio sistema de i18n.

---

## demo.html: rode a UI sem dispositivo

`demo.html` mocka a ponte `ksu.exec` para que exatamente os mesmos `vdlu.js` e `vdlu.css` rodem em um navegador comum, sem root e sem telefone:

```sh
xdg-open webui/demo.html
```

O mock simula `update.sh` e um `journal.json` em evolução, e seus botões alternam entre os cenários: uma atualização ao vivo até o DONE, um fim em `reboot_pending`, um erro no meio e uma execução cancelável. É a forma mais rápida de ver e iterar na UI, e é o que você confere antes de vendorizar o widget em um módulo.

---

## Ligando a um módulo (o gatilho de abertura da WebUI)

O `index.html` do host carrega os dois arquivos e chama três funções:

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

O host só precisa fornecer os caminhos Tier-2 e alocar um `<div>` vazio para o painel; o toast e o banner são injetados em `document.body` pelo widget. `onWebUIOpen()` é o gatilho de abertura da WebUI: é o que avalia o banner de reinício, oferece Resume em uma transação interrompida e roda a atualização automática silenciosa quando `auto_on_webui_open` está setado.

### Fonte única, re-vendorizada byte a byte

`vdlu.js` e `vdlu.css` são a **cópia canônica**. Um módulo que embarca o widget re-vendoriza esses arquivos inalterados em seu `webroot/`; ele nunca edita sua própria cópia no lugar. Um novo recurso nasce nos arquivos canônicos e flui para baixo por re-vendorização. Editar uma cópia vendorizada produz drift silencioso (já aconteceu: uma cópia obsoleta estava sem `net_policy`, o toast DEFERRED e os campos de boot-retry). Um guardião de paridade na árvore de código encontra toda cópia e sinaliza ou re-vendoriza as que divergem, cobrindo apenas o widget; o keyring tem sua própria cadência de verify-not-copy.

---

### API pública (`window.VDLU`)

| Função | Faz |
|---|---|
| `init(opts)` | configura o widget; retorna `window.VDLU` |
| `onWebUIOpen()` | chame no carregamento: banner, oferta de Resume e atualização automática silenciosa |
| `mountUpdatesPanel(el)` | renderiza o painel Updates em `el` (string de id ou elemento) |
| `check()` | roda `update.sh check`; `Promise<{update, from, to, fetch, reboot}>` |
| `startUpdate()` | dispara `run` em segundo plano mais o toast de progresso com Cancel |
| `cancel()` | cria `$VDLU_DIR/cancel` (o motor para em um ponto seguro) |
| `resume()` | resume a transação atual mais um toast |
| `refreshBanner()` | reavalia o banner persistente de reinício pendente |

---

Veja também: [[Engine]] para os comandos que o widget dirige, [[Quick Start]] para os passos completos de adoção e [[Reboot Handling]] para o que o banner está aguardando.
