# WebUI

VDLU는 선택적인 drop-in WebUI 위젯을 제공합니다: KernelSU 또는 APatch 루트 관리자 WebUI를 위한 작은 "Updates" 패널입니다. 사용자에게 Check 버튼, Update now 버튼, 취소가 가능한 라이브 진행 토스트, 재부팅 배너, 설정 패널을 제공하며, 사용자가 터미널을 전혀 건드리지 않아도 됩니다.

이것은 **바닐라 JavaScript**입니다: 프레임워크 없음, 빌드 단계 없음, CDN 없음. 세 파일입니다:

| 파일 | 무엇인지 |
|---|---|
| `vdlu.js` | 위젯, `window.VDLU`를 노출 |
| `vdlu.css` | 토스트, 배너, 패널의 스타일(다크 테마, 호스트의 CSS 변수를 상속) |
| `demo.html` | 기기 브리지를 모킹하여 전체 UI가 평범한 브라우저에서 실행되는 독립형 페이지 |

위젯은 전적으로 선택 사항입니다. [[Engine]]은 부팅 트리거에서 혼자서도 잘 실행됩니다. WebUI는 그 위의 친근한 얼굴일 뿐입니다. 모듈에 연결하는 방법은 [[Quick Start]]를 참조하세요.

---

## UI가 엔진과 대화하는 방법: `ksu.exec` 브리지

위젯은 스스로 특권적인 어떤 것도 하지 않습니다. 셸 명령을 만들어 루트 관리자의 `ksu.exec` 브리지에 넘기고, 브리지가 그것을 루트로 실행하여 stdout / stderr / 종료 코드를 반환합니다. 패널이 보여 주는 모든 것은 엔진이 쓴 파일에서 다시 읽어 옵니다.

위젯은 그 브리지를 `Promise`를 반환하는 단일 `exec(cmd)` 함수로 감쌉니다:

- 명령이 0으로 종료하면 stdout으로 **resolve**
- 그렇지 않으면 stderr(또는 `rc=N`)로 **reject**

모든 명령은 위젯이 조립한 계약(contract)의 환경을 실어 나릅니다:

```
VDLU_DIR=... MODULE_DIR=... MODID=... sh $MODULE_DIR/vdlu/update.sh <cmd>
```

몇 가지 구체적인 호출:

- **업데이트 시작:** `update.sh run`이 **백그라운드**(`(... &)`)로 실행되어, 긴 다운로드가 UI를 절대 막지 않습니다.
- **진행 상황 읽기:** `cat $VDLU_DIR/journal.json`의 가벼운 폴링(약 초당 한 번).
- **취소:** `touch $VDLU_DIR/cancel`(엔진이 다음 안전 지점에서 멈춤).
- **설정:** `$VDLU_DIR/config`(key=value) 읽기/쓰기, 순서와 알 수 없는 키를 보존하며 사용자가 바꾼 키만 건드림.

호스트가 자신의 `exec`, `toast`, `confirm` 헬퍼를 `init()`에 전달하면, 위젯은 호스트 자신의 직렬화된 명령 큐와 비주얼을 거치므로, 그 WebUI의 나머지처럼 보이고 동작합니다. 생략되면 위젯은 `ksu.exec`를 직접 호출하는 것으로 폴백하고 자체 미니 토스트를 주입합니다.

---

## 진행 토스트(취소 포함)

업데이트가 실행되면 위젯은 비차단 코너 토스트를 보여 주고 `journal.json`을 폴링합니다. 토스트는 엔진의 상태 기계를 반영합니다:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

진행 막대와 `phase done/total - current file - bytes` 한 줄을 렌더링하고, 내내 **Cancel** 버튼을 달고 있습니다. 종단 상태는 각각 고유한 처리를 받습니다:

- **DONE** -> 녹색 토스트, "vX applied - all verified".
- **PENDING_REBOOT** -> 녹색 토스트에 더해 지속적인 재부팅 배너(아래).
- **ERROR** -> `journal.error`나 stderr의 이유와 함께 빨간 토스트, Retry 제공. 절대 성공을 꾸며 내지 않음.
- **Cancelled** -> 호박색 토스트, "cancelled - N/M applied, resumable", **Resume** 제공.
- **DEFERRED** -> 부드러운 파란 정보 토스트, "download deferred, waiting for the allowed network". 이것은 오류가 아니라 무해한 네트워크 정책 대기이며, 올바른 네트워크에서 다음 check나 boot에 재개됨.

폴링은 방어적입니다. 절반만 쓰인 저널(엔진이 동시에 씀)은 잘못 파싱되는 대신 그 틱에서 무시됩니다. 진행 상황이 관찰된 뒤 저널이 사라지면 커밋이 그것을 치웠다는 뜻이므로, 위젯은 DONE을 보고합니다. 저널이 처음부터 8틱 동안 없으면 "no response"를 보고합니다. 그리고 저널이 20틱 동안 같은 값에 얼어붙으면, 위젯은 엔진의 `lock.d`를 확인합니다: 잠금이 살아 있으면 느린 단일 블롭 fetch일 뿐이므로 토스트는 계속 기다리고, 잠금이 죽어 있으면 실행이 도중에 죽은 것이므로, 위젯은 "updating"에서 영원히 돌아가는 대신 Resume 버튼과 함께 오류를 드러냅니다.

---

## 재부팅 배너

어떤 파일은 라이브 시스템에서 교체할 수 없습니다: `.so`, `/system` 오버레이, `sepolicy.rule`. 엔진은 그것들을 스테이징하고 트랜잭션을 `PENDING_REBOOT`로 표시합니다. 그러면 위젯은 **지속적인 상단 배너**를 보여 줍니다: "Reboot to activate the new `.so` (vX)". 스테이징된 파일이 다음 부팅에서 교체될 때까지 남아 있습니다. WebUI를 열 때 배너는 저널에서 다시 평가되므로, UI를 닫았다 다시 연 사용자도 여전히 그것을 봅니다. 부팅에서 무슨 일이 일어나는지는 [[Reboot Handling]]을 참조하세요.

배너는 (어떤 `.so`가 계획에 들어오는 즉시 true가 되는) `reboot_pending` 플래그가 아니라 종단 상태 `PENDING_REBOOT`에 맞춰 동작함에 유의하세요. 이것이 아무것도 실제로 스테이징되기 전에 실행 도중 배너가 나타나는 것을 막습니다.

---

## "Updates" 패널: 카테고리별 독립 토글

`mountUpdatesPanel(el)`은 호스트가 제공하는 빈 `<div>`에 설정 패널을 렌더링합니다. 세 섹션이 있고, 각 컨트롤은 독립적이며 자기 혼자 저장합니다:

**Actions**
- **Check for updates** -> `check`을 실행하여 결과를 인라인으로 보여 줌(up to date / 피드보다 최신 / 파일 개수와 reboot 태그가 있는 update available).
- **Update now** -> `run`과 진행 토스트를 발동.

**Automation**(독립 토글, 각각 뒤집히는 순간 `config`에 쓰임)
- **On WebUI open**(`auto_on_webui_open`) -> UI가 열릴 때 조용한 업데이트를 실행.
- **On reboot**(`auto_on_reboot`) -> 부팅 시 pre-zygote에서 적용.
- **Boot retry every (s)**와 **Boot retry up to (min)** -> 기기가 오프라인으로 부팅할 때 매니페스트 fetch를 재시도하기 위한 숫자 필드.

**Source**
- `source`(피드 URL), `channel`(stable / canary), `profile`(trusted / hardened), 그리고 `net_policy`(Wi-Fi + mobile / Wi-Fi only / mobile only)에 매핑되는 **Network** 선택.

토글과 숫자 필드는 즉시 저장되고 쓰기가 실패하면 시각적으로 되돌아갑니다. Source 섹션의 텍스트 및 선택 필드는 스스로를 dirty로 표시하고 명시적인 Save 버튼에서 함께 저장됩니다. 패널은 언제나 사용자가 건드린 키만 다시 쓰므로, 알 수 없거나 미래의 config 키는 보존됩니다.

### 자동 열기 동작

`onWebUIOpen()`은 호스트 로드 시 호출됩니다. 저널을 평가하고(이전 세션이 남긴 비종단 트랜잭션에 대해 재부팅 배너를 보여 주거나 Resume을 제공), 그다음 `auto_on_webui_open=1`이면 먼저 **조용한** `check()`를 실행합니다. 지속적인 진행 토스트와 실제 `run`은 할 실제 다운로드가 있을 때만(`update && fetch > 0`) 발동합니다. 기기가 up to date이거나 피드보다 앞서 있으면, 결과가 패널에 인라인으로 표시되고 화면에 토스트가 남지 않으므로, 자동 업데이트는 수동 버튼만큼 비침습적입니다.

---

## i18n(언어별 문자열)

모든 UI 문자열은 기본값이 **English**이며, 이는 공개 다국어 모듈에 중립적인 선택입니다. 전체 키 맵은 `vdlu.js`의 `DEFAULT_I18N` 객체에 있습니다(`VDLU.i18n`으로도 노출됨). 호스트는 `init({ i18n: ... })`에 맵을 전달하여 키의 어떤 부분집합이든 재정의합니다:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>
  VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x',
              i18n: window.VDLU_I18N_PT_BR });
</script>
```

- **부분** 맵도 괜찮습니다: 빠진 키는 모두 English 기본값으로 폴백합니다.
- 단계 및 상태 레이블은 `ph_<phase>`와 `st_<STATE>` 키를 사용합니다. 나머지는 `cancel`, `updateNow` 같은 평탄한 키입니다.
- 작업 예시 번역(`i18n/pt-BR.js`)이 템플릿으로 제공됩니다. 새 언어는 그저 같은 형태의 `i18n/<lang>.js` 파일이거나, 호스트가 자신의 i18n 시스템에서 맵을 만듭니다.

---

## demo.html: 기기 없이 UI 실행하기

`demo.html`은 `ksu.exec` 브리지를 모킹하여, 똑같은 `vdlu.js`와 `vdlu.css`가 루트도 폰도 없이 평범한 브라우저에서 실행되게 합니다:

```sh
xdg-open webui/demo.html
```

모킹은 `update.sh`와 진화하는 `journal.json`을 시뮬레이션하고, 그 버튼들은 시나리오 사이를 전환합니다: DONE까지 가는 라이브 업데이트, `reboot_pending` 마무리, 도중 오류, 그리고 취소 가능한 실행. UI를 보고 반복 작업하는 가장 빠른 방법이며, 위젯을 모듈에 vendor하기 전에 확인하는 것입니다.

---

## 모듈에 연결하기(WebUI-open 트리거)

호스트 `index.html`은 두 파일을 로드하고 세 함수를 호출합니다:

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

호스트는 Tier-2 경로를 제공하고 패널용으로 빈 `<div>` 하나를 할당하기만 하면 됩니다. 토스트와 배너는 위젯이 `document.body`에 주입합니다. `onWebUIOpen()`이 WebUI-open 트리거입니다: 재부팅 배너를 평가하고, 중단된 트랜잭션에 Resume을 제공하며, `auto_on_webui_open`이 설정되면 조용한 자동 업데이트를 실행하는 것입니다.

### 단일 소스, 바이트 단위로 재-vendor

`vdlu.js`와 `vdlu.css`는 **정규 사본(canonical copy)**입니다. 위젯을 임베드하는 모듈은 이 파일들을 바꾸지 않고 자신의 `webroot/`에 재-vendor합니다. 자신의 사본을 제자리에서 편집하는 일은 절대 없습니다. 새 기능은 정규 파일에서 태어나 재-vendor를 통해 흘러 내려갑니다. vendor된 사본을 편집하면 조용한 드리프트가 생깁니다(실제로 일어났습니다: 오래된 사본에 `net_policy`, DEFERRED 토스트, 부팅 재시도 필드가 빠져 있었습니다). 소스 트리의 parity 가디언이 모든 사본을 찾아 어긋난 것을 플래그하거나 재-vendor하며, 위젯만 커버합니다. keyring은 자체적인 verify-not-copy 주기를 가집니다.

---

### Public API (`window.VDLU`)

| 함수 | 하는 일 |
|---|---|
| `init(opts)` | 위젯 구성, `window.VDLU` 반환 |
| `onWebUIOpen()` | 로드 시 호출: 배너, Resume 제공, 조용한 자동 업데이트 |
| `mountUpdatesPanel(el)` | Updates 패널을 `el`(id 문자열 또는 엘리먼트)에 렌더링 |
| `check()` | `update.sh check` 실행, `Promise<{update, from, to, fetch, reboot}>` |
| `startUpdate()` | `run`을 백그라운드로 발동하고 Cancel이 있는 진행 토스트 |
| `cancel()` | `$VDLU_DIR/cancel` 생성(엔진이 안전 지점에서 멈춤) |
| `resume()` | 현재 트랜잭션을 재개하고 토스트 |
| `refreshBanner()` | 지속적인 pending-reboot 배너를 다시 평가 |

---

함께 보기: 위젯이 구동하는 명령은 [[Engine]], 전체 도입 단계는 [[Quick Start]], 배너가 무엇을 기다리고 있는지는 [[Reboot Handling]].
