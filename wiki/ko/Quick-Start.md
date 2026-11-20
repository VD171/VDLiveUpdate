# Quick Start

이것은 도입 체크리스트입니다: **VDLiveUpdate (VDLU)**를
KernelSU / APatch / Magisk 모듈에 vendor하는 방법. VDLU는 그 자체로 모듈이 아닙니다.
`<module>/vdlu/`에 넣어 여러분 모듈의 zip 안에 배포하므로, 설치된 모듈이
여러분이 게시하는 서명된 피드에서 플래시 없이 자신을 업데이트할 수 있습니다.

전반에 걸쳐, `<id>`는 여러분의 서명 키 id로, `<abi>`는 여러분이 배포하는 기기
ABI(들)(`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`)로, `<module>`은
여러분의 모듈 트리로 바꾸세요.

각 조각의 배경 논리는 [[Engine]], [[Producer]], [[WebUI]], [[Security and Trust Model]]을 참조하세요.

## 모듈 내 `vdlu/` 레이아웃

이것은 도입 후 여러분의 모듈이 지니는 정확한 트리입니다:

```
<module>/
|-- module.prop
|-- post-fs-data.sh            # pre-zygote trigger: sh "$MODDIR/vdlu/update.sh" boot
|-- webroot/
|   `-- index.html             # your WebUI, wiring the Updates panel (step 5)
`-- vdlu/
    |-- update.sh              # the engine (vendored byte-for-byte)
    |-- vdlu-verify            # ed25519 verify shim (device-side, no openssl)
    |-- verify/
    |   `-- <abi>/ed25519-mini # per-ABI verifier binary
    |-- keyring/
    |   `-- <id>.pub           # RAW 32-byte public key (NEVER the PEM)
    |-- config.default         # profile + source + automation defaults
    `-- baseline.json          # install seed (unsigned, keyless)
```

엔진의 가변 상태(`config`, `current.json`, 저널, 잠금, 블롭 캐시)는
모듈 디렉터리 밖의 Tier-2인 `/data/adb/<modid>/vdlu/`에 있습니다.
`config.default`는 첫 실행 시 그 Tier-2 `config`를 seed합니다. 전체 상태 레이아웃은
[[Engine]]을 참조하세요.

## 1. 엔진 vendor하기

엔진, verify shim, 그리고 ABI별 검증기 바이너리를
`<module>/vdlu/`에 복사합니다:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh   <module>/vdlu/update.sh
cp engine/vdlu-verify <module>/vdlu/vdlu-verify
cp -r verify/<abi>    <module>/vdlu/verify/<abi>    # ed25519-mini per ABI
```

여러분이 지원하는 ABI만 배포하세요. `customize.sh`가 설치 시점에 `verify/`를
기기의 ABI로 정리할 수 있습니다.

## 2. 서명 키 생성(일회성)

```sh
producer/vdlu-keygen <id> ./keys
```

이것은 세 파일을 내보냅니다:

- `<id>.pem` - 개인 키. 모든 기기에서 떨어뜨려 두고 어떤 저장소
  푸시나 CI 시크릿에도 넣지 마세요.
- `<id>.pub` - PEM 공개 키. PC 측 전용(`vdlu-sign`이 사용).
- `<id>.pub.raw` - 원시 32바이트 공개 키, 기기 keyring용.

이 분리가 왜 중요한지는 [[Security and Trust Model]]을 참조하세요.

## 3. 원시 공개 키 내장하기

기기 keyring은 PEM이 아니라 **원시 32바이트** 키를 보관합니다. `ed25519-mini`는
PEM을 읽을 수 없으므로, PEM을 여기 복사하면 기기 내 검증이 깨집니다:

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

keyring은 릴리스 전반에 걸쳐 안정적입니다: 오직 키 회전에서만 바뀝니다.
재-vendor 시 **덮어쓰지 말고 검증하세요**.

## 4. config 작성하기

`config.default`를 `<module>/vdlu/`에 배포합니다. 이것은 첫 실행 시 Tier-2 `config`를
seed합니다:

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

`profile=trusted`는 비공개 `file://` 또는 SSH 소스에만 사용하세요(거기서는 verify가
best-effort이지만, 모든 블롭의 sha256은 여전히 확인됩니다). 글자 그대로의 `trusted`가
아닌 어떤 값이든 `hardened`로 취급되어 fail-closed입니다. 전체 프로필 의미론은
[[Security and Trust Model]]을 참조하세요.

## 5. 트리거 연결하기

**재부팅 시**(`auto_on_reboot`): `post-fs-data.sh`에서 엔진을 pre-zygote로
호출하여, 스테이징된 reboot 클래스 파일(`.so`, `/system` 오버레이,
`sepolicy.rule`)이 추가 재부팅 없이 교체되게 합니다:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**WebUI 열기 시**(`auto_on_webui_open`): drop-in Updates 패널을 여러분의
`webroot/index.html`에 연결합니다:

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
  VDLU.onWebUIOpen();                                            // journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // the "Updates" tab
</script>
```

`vdlu.js`와 `vdlu.css`는 `webui/`에서 vendor됩니다. 번역은
`i18n: window.VDLU_I18N_<LANG>`으로 추가할 수 있습니다. 패널 계약은 [[WebUI]]를 참조하세요.

## 6. 릴리스 워크플로에서 피드 서명하기

릴리스마다, 최종 모듈 트리를 pack하고 매니페스트에 서명합니다. 개인
키는 CI가 아니라 운영자 머신에 두세요:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> \
                    --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

`vdlu-pack`은 콘텐츠 주소화와 중복 제거를 하므로, 게시는 증분적입니다:
변경되지 않은 블롭은 절대 다시 푸시되지 않습니다. [[Producer]]와 [[Feed Format]]을 참조하세요.

## 7. baseline 배포하기

배포 트리에 대해 `baseline.json`을 생성하여
`<module>/vdlu/baseline.json`에 둡니다. 이것은 새 설치에서 `current.json`을 seed하므로,
기기가 "current" 상태로 태어나 자신의 배포 버전을 다시 가져오지 않습니다. 이것은
**로컬 신뢰 seed**입니다: 서명되지 않고 키 없이이므로, CI가 서명 키에 한 번도
닿지 않고 빌드할 수 있습니다:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

없어도 치명적이지 않습니다: 기기는 그저 첫 업데이트에서 버전 `0`에서
시작합니다.

---

이것이 도입 전부입니다. 배포하기 전에 `sh -n <module>/vdlu/update.sh`가
통과해야 하며, [[Contributing]]과 [[Producer]]에 나온 대로 producer와 엔진을
처음부터 끝까지 테스트해야 합니다.
