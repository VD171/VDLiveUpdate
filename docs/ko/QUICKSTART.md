> **Languages:** [English](../QUICKSTART.md) · [العربية](../ar/QUICKSTART.md) · [Čeština](../cs/QUICKSTART.md) · [Deutsch](../de/QUICKSTART.md) · [Español](../es/QUICKSTART.md) · [فارسی](../fa/QUICKSTART.md) · [Français](../fr/QUICKSTART.md) · [हिन्दी](../hi/QUICKSTART.md) · [Bahasa Indonesia](../id/QUICKSTART.md) · [Italiano](../it/QUICKSTART.md) · [日本語](../ja/QUICKSTART.md) · 한국어 · [Nederlands](../nl/QUICKSTART.md) · [Polski](../pl/QUICKSTART.md) · [Português](../pt/QUICKSTART.md) · [Русский](../ru/QUICKSTART.md) · [Svenska](../sv/QUICKSTART.md) · [ไทย](../th/QUICKSTART.md) · [Türkçe](../tr/QUICKSTART.md) · [Українська](../uk/QUICKSTART.md) · [Tiếng Việt](../vi/QUICKSTART.md) · [中文](../zh/QUICKSTART.md)

---

# VDLU 도입 퀵스타트

**VDLiveUpdate**를 모듈에 벤더링하기 위한 복사-붙여넣기 체크리스트. VDLU는 그 자체로 모듈이 아니다:
`<module>/vdlu/`에 넣어지며 당신 모듈의 zip 안에 담겨 출시된다. 전체 근거는
[`INTERFACES.md`](INTERFACES.md) (seam 계약), [`ENGINE.md`](ENGINE.md),
[`PRODUCER.md`](PRODUCER.md), [`WEBUI.md`](WEBUI.md)를 참조하라.

`<id>`는 당신의 서명 키 id로, `<abi>`는 당신이 출시하는 기기 ABI (`arm64-v8a`, `armeabi-v7a`,
`x86_64`, `x86`)로, `<module>`은 당신의 모듈 트리로 바꾸라.

## 대상 레이아웃

도입 후 모듈이 담게 되는 정확한 `vdlu/` 트리는 다음과 같다:

```
<module>/
├── module.prop
├── post-fs-data.sh            # pre-zygote 트리거: sh "$MODDIR/vdlu/update.sh" boot
├── webroot/
│   └── index.html             # Updates 패널을 연결하는 당신의 WebUI (5단계)
└── vdlu/
    ├── update.sh              # 엔진 (바이트 단위로 벤더링됨)
    ├── vdlu-verify            # ed25519 검증 shim (기기 측, openssl 없음)
    ├── verify/
    │   └── <abi>/ed25519-mini # ABI별 검증 바이너리
    ├── keyring/
    │   └── <id>.pub           # RAW 32바이트 공개키 (결코 PEM이 아님)
    ├── config.default         # profile + source + 자동화 기본값
    └── baseline.json          # 설치 seed (서명 없음, 키 없음)
```

엔진의 가변 상태 (`config`, `current.json`, 저널, 락)는 모듈 디렉터리 밖의 Tier-2,
`/data/adb/<modid>/vdlu/`에 있다. `config.default`가 첫 실행 때 그것을 seed한다.

## 1. 엔진 벤더링

엔진, 검증 shim, ABI별 검증기를 `<module>/vdlu/`에 복사하라:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh      <module>/vdlu/update.sh
cp engine/vdlu-verify    <module>/vdlu/vdlu-verify
cp -r verify/<abi>       <module>/vdlu/verify/<abi>      # ABI별 ed25519-mini
```

당신이 지원하는 ABI만 출시하라. `customize.sh`가 설치 시점에 `verify/`를 기기의 ABI로 가지치기할 수 있다.

## 2. 서명 키 생성 (일회성)

```sh
producer/vdlu-keygen <id> ./keys
```

이것은 `<id>.pem` (개인, 모든 기기와 모든 저장소 푸시에서 떼어 둘 것), `<id>.pub` (PEM, PC 측 전용),
그리고 `<id>.pub.raw` (RAW 32바이트, 기기 keyring용)를 방출한다.

## 3. raw 공개키 임베드

기기 keyring은 **RAW 32바이트** 키를 보유하며, 결코 PEM이 아니다 (`ed25519-mini`는 PEM을 읽을 수 없음):

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

keyring은 릴리스를 가로질러 안정적이다 (키 로테이션에서만 변경됨): 재벤더링 시, 덮어쓰지 말고 **검증하라**.

## 4. config 작성

`config.default`를 `<module>/vdlu/`에 출시하라 (첫 실행 때 Tier-2 `config`를 seed함):

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # 공개 피드: 서명 필수, 다운그레이드 차단
net_policy=any
pubkey_dir=keyring
# apply_busy_file=/data/adb/<modid>/.busy   # 옵트인: 이 경로가 존재하는 동안 APPLY 지연 (예: 실행 중인 백업)
```

`profile=trusted`는 사설 `file://`/SSH 소스에만 사용하라 (검증은 best-effort. 모든 blob의 sha256은
여전히 검사됨). 리터럴 `trusted` 이외의 어떤 값이든 `hardened`로 취급된다 (fail-closed).

## 5. 트리거 연결

**reboot 시** (`auto_on_reboot`): `post-fs-data.sh`에서 엔진을 pre-zygote로 호출하여 스테이징된 파일
(`.so`, `/system` 오버레이, `sepolicy.rule`)이 추가 reboot 없이 교체되도록 하라:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**WebUI 열림 시** (`auto_on_webui_open`): 당신의 `webroot/index.html`에 드롭인 Updates 패널을 연결하라:

```html
<link rel="stylesheet" href="vdlu.css">
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,
    vdluDir:   '/data/adb/' + MODID + '/vdlu',
    modid:     MODID,
    module:    'YourModule'
  });
  VDLU.onWebUIOpen();                                             // 저널 + 배너 + auto_on_webui_open 평가
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // "Updates" 탭
</script>
```

(`vdlu.js` / `vdlu.css`는 `webui/`에서 벤더링된다. 번역은 `i18n: window.VDLU_I18N_<LANG>`로 추가할 수 있다.)

## 6. 릴리스 워크플로에서 피드 서명

릴리스마다 최종 모듈 트리를 패킹하고 manifest에 서명하라. 개인 키는 운영자 머신에 두고, 결코 CI에 두지 말 것:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]        # delete[] = prev 이후 사라진 경로
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# ./out/{manifest.json,blobs/}를 <source>에 퍼블리시
```

## 7. 베이스라인 출시

출시 트리에 대해 `baseline.json`을 생성하고 `<module>/vdlu/baseline.json`에 배치하라. 이것은 새로
설치할 때 `current.json`을 seed하여 기기가 "current"로 태어나도록 한다 (재가져오기 없음). 이것은
**로컬의 신뢰된 seed**다: 서명도 키도 없으므로, CI는 서명 키를 결코 건드리지 않고도 그것을 빌드할 수 있다:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

없어도 치명적이지 않다 (기기는 첫 업데이트에서 단지 `0`부터 시작할 뿐이다).

---

이것이 도입의 전부다. `sh -n <module>/vdlu/update.sh`는 반드시 통과해야 한다. 출시 전에
[`PRODUCER.md`](PRODUCER.md)와 루트 README에 보인 대로 프로듀서와 엔진을 종단 간으로 테스트하라.

<!-- doc-footer -->

---

> _이 문서는 Claude (Anthropic)로 생성되었으며 VD171이 유지 관리합니다. 수정 및 개선을 환영합니다. [CONTRIBUTING.md](CONTRIBUTING.md)를 참조하세요._
