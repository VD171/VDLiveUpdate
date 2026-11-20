# Contributing

기여를 환영합니다. VDLU는 KernelSU / APatch / Magisk 모듈에 vendor되는
플래시 없는 증분 자가 업데이트 엔진입니다. 이 페이지는 실용적인 개발
워크플로입니다. 조각들이 어떻게 맞물리는지는 [[Architecture]], [[Engine]],
[[Producer]]를 먼저 읽으세요.

## 컴파일할 것이 없음

VDLU는 스크립트입니다(POSIX sh, 릴리스 측의 약간의 Python, WebUI를 위한 바닐라 JS).
그래서 빌드 단계가 없습니다. 변경은 파이프라인을 처음부터 끝까지 실행하고
각 조각을 정적 검사하여 검증합니다.

## 이음새 계약 먼저

구성요소 사이의 인터페이스 계약(엔진, producer, WebUI가 공유하는 CLI 서명, 파일명,
JSON 키)은 **수렴의 법칙(law of convergence)**입니다. 불변으로 취급하세요. 변경이
producer-엔진 이음새(매니페스트 스키마, 저널 스키마, config 키,
서명/정규화 규칙)를 건드리면, **인터페이스 계약을 먼저 맞춘** 다음
양쪽 코드를 일치하도록 바꾸세요. 이음새 한쪽만의 변경은 다른 쪽 없이
조용히 도입자를 망가뜨립니다. 서명기와 검증기가 바이트 단위로 합의해야 하는
정규화 규칙은 [[Producer]]를 참조하세요.

## PR 전에 처음부터 끝까지 테스트

producer와 엔진을 일회용 트리에서 함께 실행하세요, 도입자의 릴리스가 하는
것과 같은 방식으로:

```sh
# 1. a signing key
producer/vdlu-keygen demo /tmp/k

# 2. pack a module tree into a feed
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1

# 3. sign the manifest in place
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo

# 4. verify the manifest the way the device will (RAW 32B keyring)
engine/vdlu-verify /tmp/feed/manifest.json /tmp/keyring

# 5. drive the engine against the feed (source=file:///tmp/feed in the config)
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

그다음 각 구성요소를 정적 검사하세요:

```sh
sh -n engine/*.sh            # POSIX sh syntax, must pass
node --check webui/vdlu.js   # WebUI JS syntax
```

그리고 `webui/demo.html`을 브라우저에서 여세요: 그것은 루트 관리자 브리지
(`ksu.exec`)를 모킹하므로, 기기 없이 Updates 패널, 진행 토스트, 취소,
재부팅 배너를 시험해 볼 수 있습니다. [[WebUI]]를 참조하세요.

## 집안 규칙

- **기기에서 POSIX sh.** `local`을 넘는 bashism 없음, `jq` 없음. toybox / busybox에서
  실행되어야 합니다.
- **보안은 타협 불가.** 모든 매니페스트 필드는 적대적 입력입니다.
  `validate_plan()`은 fail-closed로 남고, 개인 서명 키는 CI나 기기에 절대
  닿지 않습니다. 테스트를 통과시키려고 검사를 느슨하게 하지 마세요.
- **실패에 엄격.** 트랜잭션을 재개 가능하게 유지하세요: 일치하는 재해시 없이는
  어떤 것도 "done"을 보고하지 않고, 백업 없이는 어떤 것도 덮어쓰지 않으며,
  적용은 원자적으로 유지됩니다.
- **항상 릴리스 품질.** 주석은 간결하게 유지하세요. 불필요한 주석은 금물.
- **PR당 하나의 논리적 변경.** 무엇이 왜 바뀌었는지 말하세요.

## 이슈 제기

무엇을 했고, 무엇을 기대했으며, 무엇이 일어났는지 설명하는 이슈를 여세요.
버그의 경우, 모듈 id, 소스 프로필(`hardened` 또는 `trusted`),
실행한 `update.sh` 명령, 그리고 관련 `journal.json`(단계, 상태, 오류를 기록함)을
포함하세요. 기능의 경우, 그것이 어느 구성요소(엔진, producer, 또는 WebUI)를
건드리는지 말하여 이음새 영향이 처음부터 명확하게 하세요.
