> **Languages:** [English](../WEBUI.md) · [العربية](../ar/WEBUI.md) · [Čeština](../cs/WEBUI.md) · [Deutsch](../de/WEBUI.md) · [Español](../es/WEBUI.md) · [فارسی](../fa/WEBUI.md) · [Français](../fr/WEBUI.md) · [हिन्दी](../hi/WEBUI.md) · [Bahasa Indonesia](../id/WEBUI.md) · [Italiano](../it/WEBUI.md) · [日本語](../ja/WEBUI.md) · 한국어 · [Nederlands](../nl/WEBUI.md) · [Polski](../pl/WEBUI.md) · [Português](../pt/WEBUI.md) · [Русский](../ru/WEBUI.md) · [Svenska](../sv/WEBUI.md) · [ไทย](../th/WEBUI.md) · [Türkçe](../tr/WEBUI.md) · [Українська](../uk/WEBUI.md) · [Tiếng Việt](../vi/WEBUI.md) · [中文](../zh/WEBUI.md)

---

# VDLU - WebUI 위젯 (flashless 업데이트)

KernelSU/APatch root 매니저 WebUI를 위한 VDLU (VD Live Update) 인터페이스. Vanilla JS, 프레임워크 없음,
빌드 없음, CDN 없음. 드롭인: 호스트의 `index.html`이 2개 파일을 로드하고 API를 호출한다.

수렴: `INTERFACES.md` §9 (WEBUI↔ENGINE), §4 (journal.json), §5 (config).

## 파일

| 파일 | 내용 |
|---|---|
| `vdlu.js` | 컴포넌트 - `window.VDLU`를 노출한다 |
| `vdlu.css` | 진행 토스트, reboot 배너, "Updates" 탭 (다크 테마, 호스트의 변수를 상속함) |
| `demo.html` | 모킹된 `ksu.exec`를 가진 독립 페이지 - 브라우저에서 열림, 기기 불필요 |

## 호스트 `index.html`로의 통합

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

### 호스트가 정의해야 하는 것

- **`moduleDir`** = `$MODULE_DIR` (`/data/adb/modules/<modid>`), 엔진이 벤더링되는 곳
  (`vdlu/update.sh`).
- **`vdluDir`** = `$VDLU_DIR` (`/data/adb/<modid>/vdlu`), Tier-2 상태 (`journal.json`, `config`,
  `cancel`).
- **`modid`** = 모듈 id.

위젯은 계약의 env (§1)를 이미 지닌 엔진 명령을 조립한다:
`VDLU_DIR=… MODULE_DIR=… MODID=… sh $MODULE_DIR/vdlu/update.sh <cmd>`. `run`/`resume`은
**백그라운드** (`(… &)`)로 가고, 진행 상황은 `cat $VDLU_DIR/journal.json`의 가벼운 폴링 (약 1초)으로 읽힌다.

### `exec`/`toast`/`confirm` (선택)

생략되면 위젯은 자체의 것을 사용한다:
- **`exec(cmd)`**는 stdout (rc 0)으로 **resolve**하고 stderr (rc≠0)로 **reject**하는 `Promise`를 반환해야 한다 -
  정확히 Demo `webroot/index.html`의 `ex()`의 시그니처. 내부 폴백은 같은 계약으로
  `ksu.exec(cmd, '{}', cb)`를 호출한다.
- **`toast(msg)`** = 짧은 일시적 알림 (폴백은 자체 미니 토스트를 주입함).
- **`confirm(title,msg,ok,danger,fn)`** = 모달 (오늘은 호스트만 사용함. 위젯은 어떤 흐름에서도
  확인을 요구하지 않음).

호스트 자신의 것을 전달하면 위젯은 WebUI의 나머지와 **같은** 직렬화 큐와 비주얼을 통해 대화한다.

## 공개 API (`window.VDLU`)

| 함수 | 동작 |
|---|---|
| `init(opts)` | 설정한다 (위 참조). `window.VDLU`를 반환한다. |
| `onWebUIOpen()` | load 시 호출: `reboot_pending`이면 배너를 표시한다. 비종단 트랜잭션이 있으면 **Resume**을 제공한다. `auto_on_webui_open=1`이면 **QUIET 자동 업데이트**를 실행한다 (먼저 조용한 `check()`. `update && fetch>0`일 때만 `run`+영구 토스트를 실행함 - 최신/ahead = 패널 내 인라인 결과, 토스트 제로). |
| `mountUpdatesPanel(el)` | `el` (문자열 id 또는 요소) 안에 "Updates" 탭을 렌더링한다: **Check for update**, **Update now**, `auto_on_webui_open`/`auto_on_reboot` 토글, boot-retry 필드, **Network** 셀렉트 (`net_policy`: Wi-Fi+mobile / Wi-Fi-only / mobile-only), `source`/`channel`/`profile` 필드. |
| `check()` | `update.sh check`를 실행한다. `Promise<{update,from,to,fetch,reboot}>`. |
| `startUpdate()` | `run`을 백그라운드로 실행 + **Cancel**이 있는 진행 토스트. |
| `cancel()` | `$VDLU_DIR/cancel`을 생성한다 (엔진은 안전 지점에서 멈춤). |
| `resume()` | `update.sh resume` + 토스트 (현재 단계부터 재개함). |
| `refreshBanner()` | 영구적인 pending-reboot 배너를 재평가한다. |

토스트 (모서리 오버레이, 비차단)와 배너 (상단, 영구)는 위젯이 `document.body`에
주입한다 - 호스트는 그것들을 위한 HTML이 필요 없다. "Updates" 탭은 호스트가 할당하는 유일한 지점이다 (빈
`<div>`).

### 토스트가 반영하는 상태 흐름 (journal.json, §4)

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)`. 언제든 `ERROR`.
토스트는 **바 + `phase done/total · current · bytes`**를 표시한다. 종단:
- **`DONE`** → 초록 토스트 "v&lt;target&gt; applied".
- **`PENDING_REBOOT`** (또는 `reboot_pending=true`) → 초록 토스트 + **영구 배너** "⚠️ Reboot to
  activate the new `.so` (vX)".
- **`ERROR`** → 이유가 있는 빨간 토스트 (`journal.error`/stderr). 결코 성공을 위조하지 않음.
- **Cancelled** → "cancelled - N/M, resumable" + **Resume** 버튼.

## 데모 실행

`demo.html`을 브라우저에서 연다 (`xdg-open webui/demo.html`). 모킹된 `ksu.exec`는 `update.sh`와
`journal.json`이 진화하는 것을 시뮬레이션한다. 버튼들은 **LIVE→DONE**, **reboot_pending**, **error mid-way**,
**cancellable** 시나리오 사이를 전환한다. 기기에서와 같은 `vdlu.js`/`vdlu.css`다.

## i18n (언어)

위젯 문자열은 기본적으로 **영어** (공개 다국어 모듈에 중립적). 호스트는 `init`에 맵을 전달하여
어떤 키든 재정의한다:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- **부분** 병합도 괜찮다: 없는 키는 영어 기본값으로 폴백한다.
- 단계/상태 키는 `ph_<phase>` / `st_<STATE>`. 나머지는 플랫 (`cancel`, `updateNow`, …).
- 전체 키 맵 = `vdlu.js`의 `DEFAULT_I18N` 객체 (`VDLU.i18n`로도 노출됨).
- 작업 예시로, 완성된 번역이 제공된다: `i18n/pt-BR.js`. 새 언어 = 같은 틀의
  `i18n/<lang>.js` 파일, 또는 호스트가 자체 i18n 시스템에서 맵을 구축함.

## 단일 소스 (모듈 간 패리티)

이 `vdlu.js`/`vdlu.css`는 **정규 사본**이다. 위젯을 임베드하는 모든 모듈은,
이 사본을 바이트 단위로 자신의 `webroot/`에 **재벤더링**한다 - 자신의 것을 제자리에서 **결코** 편집하지 않는다.
새 위젯 기능은 여기서 태어나 재벤더링으로 하류로 흐른다. 반대는 조용한 드리프트를 낳는다 (실제로 발생함: 벤더링된 사본이
뒤처져 `net_policy`, `DEFERRED` 토스트, `boot_retry` 필드를 누락했음).

가디언: [`../tools/webui-parity.sh`](../../tools/webui-parity.sh)은 소스 트리의 모든 사본을 찾아,
정규의 것과 갈라진 것을 지적한다 (`vdlu.js`/`vdlu.css`만. keyring은 "복사가 아니라 검증").

```sh
tools/webui-parity.sh         # report; exits 1 if there is drift
tools/webui-parity.sh --fix   # re-vendors the divergent ones from the canonical
```

> 🪤 keyring (`keyring/<id>.pub` RAW 32B)과 엔진 (`vdlu/update.sh`)은 각자의 재벤더링 주기를 가진다.
> 이 가디언이 커버하는 것은 **WebUI 위젯뿐**이다.

<!-- doc-footer -->

---

> _이 문서는 Claude (Anthropic)로 생성되었으며 VD171이 유지 관리합니다. 수정 및 개선을 환영합니다. [CONTRIBUTING.md](CONTRIBUTING.md)를 참조하세요._
