> **Languages:** [English](../../SECURITY.md) · [العربية](../ar/SECURITY.md) · [Čeština](../cs/SECURITY.md) · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · [فارسی](../fa/SECURITY.md) · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · [Italiano](../it/SECURITY.md) · [日本語](../ja/SECURITY.md) · 한국어 · [Nederlands](../nl/SECURITY.md) · [Polski](../pl/SECURITY.md) · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · [中文](../zh/SECURITY.md)

---

# 보안 정책

VDLiveUpdate (VDLU) 는 실행 중인 모듈에 flashless root 업데이트를 적용합니다. 모듈 자체
디렉터리에 기록하고 부팅 시 Zygisk `.so` 를 교체하며, 모듈의 root 컨텍스트에서 실행됩니다.
우리는 보안을 진지하게 생각합니다.

## 취약점 신고

- **Site:** https://vd171.ru
- **Site:** https://vd.priv8.ru
- **Issues:** https://github.com/VD171/VDLiveUpdate/issues
- **GitHub:** [@VD171](https://github.com/VD171)
- **XDA-Developers:** [@VD171](https://xdaforums.com/m/vd171.4699873/)
- **Telegram:** [@VD_Priv8](https://t.me/VD_Priv8)
- **Channel:** [@Priv8_VD](https://t.me/Priv8_VD)
- **Discord:** [@VD.Priv8](https://discord.com/users/1296831918989639721)
- **E-mail:** vd.priv8@pm.me

명확한 설명과, 가능하다면 문제를 재현하는 manifest 또는 feed 를 포함해 주세요. 최대한 빨리
응답하며, 원하시면 귀하를 크레딧에 표기합니다.

## 범위 참고 사항

- 업데이트는 content-addressed 블롭과 ed25519 로 서명된 `manifest.json` 입니다. 기기는
  내장된 `ed25519-mini` 로 서명을 검증하며 (기기에 openssl 없음), 각 블롭은 사용되기 전에
  자신의 `sha256` 과 대조됩니다.
- hardened 프로필 (공개 기본값) 은 유효한 서명을 요구하고 downgrade 를 차단합니다. "시작"
  버전은 설치된 모듈의 `versionCode` (`module.prop` 에서 읽음) 로 하한이 정해지므로, 모듈이
  feed 보다 뒤로 되돌려지는 일은 없습니다.
- 신뢰 루트 (`keyring/` 의 원시 ed25519 공개 키와 `verify/` 의 바이너리) 는 flash 전용이며
  네트워크를 통해 회전되지 않습니다. 생산자는 이를 feed 에서 제외하고 engine 은 가져온
  계획의 모든 `vdlu/` 경로를 무시하므로, 유출된 서명 키가 검증기나 키를 교체하여 root 를
  유지할 수 없습니다.
- 다른 모듈용으로 유효하게 서명된 manifest 는 다른 모듈의 디렉터리에 쓸 수 없습니다. 서명된
  `module` 필드는 기기의 `MODID` 와 같아야 하며 (모듈 간 바인딩 검사), 모든 쓰기와 삭제는
  모듈 디렉터리로 제한됩니다.
- engine 은 모듈 자체의 root 컨텍스트에서 실행되며 이를 결코 약화시키지 않습니다. 어떤
  권한도 추가하지 않고 manifest 의 어떤 필드도 shell 에 삽입하지 않으며, `path`, `sha256`,
  `mode`, `delete[]` 의 각 값은 사용 전에 적대적 입력으로 검증됩니다.
- 태세는 fail-closed 입니다. 손상되었거나 알 수 없는 `profile` 값이 서명되지 않은 콘텐츠를
  수락하는 쪽으로 빠지는 일은 결코 없으며 (정확히 `trusted` 가 아닌 것은 모두 `hardened` 로
  취급), 어떤 파일이든 덮어쓰기 전에 백업이 기록되므로 실패한 apply 가 설치된 버전을
  파괴하는 일은 없습니다.
- 전체 신뢰 모델, fail-closed 보장 및 hardening 세부 사항은 [TRUST-MODEL.md](TRUST-MODEL.md)
  를 참조하세요.

<!-- doc-footer -->

---

> _이 문서는 Claude (Anthropic)로 생성되었으며 VD171이 유지 관리합니다. 수정 및 개선을 환영합니다. [CONTRIBUTING.md](CONTRIBUTING.md)를 참조하세요._
