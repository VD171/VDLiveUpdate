> **Languages:** [English](../../CONTRIBUTING.md) · [العربية](../ar/CONTRIBUTING.md) · [Čeština](../cs/CONTRIBUTING.md) · [Deutsch](../de/CONTRIBUTING.md) · [Español](../es/CONTRIBUTING.md) · [فارسی](../fa/CONTRIBUTING.md) · [Français](../fr/CONTRIBUTING.md) · [हिन्दी](../hi/CONTRIBUTING.md) · [Bahasa Indonesia](../id/CONTRIBUTING.md) · [Italiano](../it/CONTRIBUTING.md) · [日本語](../ja/CONTRIBUTING.md) · 한국어 · [Nederlands](../nl/CONTRIBUTING.md) · [Polski](../pl/CONTRIBUTING.md) · [Português](../pt/CONTRIBUTING.md) · [Русский](../ru/CONTRIBUTING.md) · [Svenska](../sv/CONTRIBUTING.md) · [ไทย](../th/CONTRIBUTING.md) · [Türkçe](../tr/CONTRIBUTING.md) · [Українська](../uk/CONTRIBUTING.md) · [Tiếng Việt](../vi/CONTRIBUTING.md) · [中文](../zh/CONTRIBUTING.md)

---

# VDLiveUpdate에 기여하기

VDLU는 KernelSU/APatch/Magisk 모듈에 벤더링되는, flashless하고 증분적인 자가 업데이트 엔진이다.
기여를 환영한다.

- 먼저 [INTERFACES.md](INTERFACES.md)를 읽을 것: 이것은 컴포넌트 사이의 이음새 계약이다 (수렴의
  법칙). 엔진, 프로듀서, WebUI를 가로질러 조율된 변경이 아닌 한 이를 불변으로 취급할 것.
- PR 전에 엔드투엔드로 테스트할 것: `producer/vdlu-keygen`, `vdlu-pack`, `vdlu-sign`, 그다음 엔진
  (`check` / `run` / `boot`). 또한 `sh -n engine/*.sh`와 `node --check webui/vdlu.js`.
- 보안은 타협 불가: 모든 manifest 필드는 적대적 입력이며 `validate_plan()`은
  fail-closed로 유지된다. 비밀 서명 키는 결코 CI나 기기에 닿지 않는다.
- 기기에서는 POSIX sh (`local` 이외의 bashism 없음, `jq` 없음). 주석은 간결하게 유지할 것.
- PR당 하나의 논리적 변경. 무엇이 바뀌었고 왜인지를 말할 것.

## 연락처

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- Channel: @Priv8_VD https://t.me/Priv8_VD
- E-mail: vd.priv8@pm.me

<!-- doc-footer -->

---

> _이 문서는 Claude (Anthropic)로 생성되었으며 VD171이 유지 관리합니다. 수정 및 개선을 환영합니다. [CONTRIBUTING.md](CONTRIBUTING.md)를 참조하세요._
