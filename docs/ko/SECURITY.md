> **Languages:** [English](../SECURITY.md) · [العربية](../ar/SECURITY.md) · [Čeština](../cs/SECURITY.md) · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · [فارسی](../fa/SECURITY.md) · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · [Italiano](../it/SECURITY.md) · [日本語](../ja/SECURITY.md) · 한국어 · [Nederlands](../nl/SECURITY.md) · [Polski](../pl/SECURITY.md) · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · [中文](../zh/SECURITY.md)

---

# 보안 정책 및 신뢰 모델

VDLiveUpdate (VDLU)는 라이브 모듈에 **flashless root 업데이트**를 적용한다: `/data/adb/modules/<mod>`에
기록하고 boot에서 Zygisk `.so`를 교체한다. 가져온 manifest의 모든 필드 (`path`, `sha256`, `delete[]`,
`mode`, ...)는 **적대적 입력**이다 - 오염된 피드나 MITM이 그것을 전달한다. 이 페이지는 신뢰 모델이자
책임 있는 공개 정책이다. 전체 seam 계약은 [`INTERFACES.md`](INTERFACES.md)를, 엔진/프로듀서 내부는
[`ENGINE.md`](ENGINE.md)와 [`PRODUCER.md`](PRODUCER.md)를 참조하라. 위키 페이지
**Security-and-Trust-Model**은 저장소 밖의 독자를 위해 같은 모델을 담고 있다.

## 지원 버전

보안 수정은 최신 `ENGINE_VERSION`에 안착한다. 서명된 manifest는 `engine_min`으로 자신이 필요로 하는
최소 엔진을 선언하며, 기기 상의 엔진은 자신이 구현한 것보다 더 많은 것을 요구하는 manifest를 거부한다.
오래된 벤더링 엔진은 제자리에서 백패치되는 것이 아니라, 수정을 가져오기 위해 **재벤더링**할 것으로
기대된다.

| ENGINE_VERSION | 상태 |
|---|---|
| 4 (현재) | 지원됨 - `key_id` allowlist, dot-segment/trailing-slash 경로 거부, 크기 상한, check 시점 락 |
| 3 | 대체됨 - `hardened` 기본값, 반전에 의한 fail-closed `profile`, 모듈/MODID 바인드, 다운그레이드 차단 |
| <= 2 | 미지원 - 현재 엔진으로 재벤더링할 것 |

엔진 검증 또는 적용 로직의 어떤 변경이든 `ENGINE_VERSION`을 올린다.

## 취약점 신고

비공개로 신고하라. 보안 버그에 대해 공개 이슈, PR, 포럼 게시물을 **열지 말 것**. 프로젝트 연락처를
사용하라 ([`CONTRIBUTING.md`](../CONTRIBUTING.md) 참조):

- Telegram: **@VD_Priv8** (https://t.me/VD_Priv8)
- 채널: **@Priv8_VD** (https://t.me/Priv8_VD)
- E-mail: **vd.priv8@pm.me**

엔진 버전, 사용 중인 `profile`, 그리고 문제를 재현하는 manifest 또는 피드를 포함해 주기 바란다. 수정은
`CHANGELOG.md` 항목과 함께 새 `ENGINE_VERSION`으로 출시된다. 공개 시점은 신고 스레드에서 조율하라.

## 신뢰 모델

- **분리된 ed25519 서명.** 프로듀서는 PC에서 정규 manifest에 서명하고 (openssl), 기기는 내장
  `ed25519-mini`로 검증한다 - **기기에 openssl 없음**. 서명되는 메시지는 `sig` 필드를 뺀 manifest의
  sha256 16진수 (키 정렬, 컴팩트, UTF-8)이므로, 서명과 검증은 기기에 JSON 라이브러리 없이도 두 런타임에서
  같은 바이트를 도출한다.
- **keyring = RAW 32바이트 공개키**, 플래시 전용. 기기 keyring은 `<key_id>.pub`를 raw 32바이트 키로
  (결코 PEM이 아니라) 출시한다. `vdlu-pack`은 keyring과 `verify/` 바이너리를 피드에서 **제외**하므로,
  manifest가 기기 상의 신뢰 앵커를 유선으로 다시 쓰는 일은 결코 있을 수 없다.
- **모듈 업데이트 `key_id` allowlist (fail-closed, pubkey 선택 전).** keyring은 정당하게 둘 이상의 키를
  담을 수 있다 (예를 들어 release 키 옆의 신뢰도가 낮은 fingerprint-feed 키). `<key_id>.pub`가 선택되기도
  전에, `verify_manifest`는 그 `key_id`가 구성된 allowlist에 없는 manifest를 **두 profiles 모두**에서
  거부하며, 해결된 집합을 `VDLU_KEYID_ALLOW`를 통해 `vdlu-verify`에 미러링한다. 이는 유출된 신뢰도 낮은
  키가 전체 flashless root 업데이트에 서명할 수도 있었던 우회를 막는다. `key_id`가 설정되지 않았을 때
  기본 안전: **단일 키** keyring은 그 하나의 키로 자동 고정되고, **다중 키** keyring은 `key_id`가 고정될
  때까지 거부된다 (로테이션을 위해 쉼표로 구분).
- **fingerprint-feed 신뢰 루트는 자체 키를 가진 별개의, 고정된 경로**이며, 위의 모듈 업데이트 경로를 통해서는
  결코 도달할 수 없다.
- **베이스라인은 로컬의 신뢰된 seed다.** `baseline.json`은 플래시된 zip 안에 도착한다 - 설치 신뢰 경계 -
  따라서 서명도 키도 없으며 `vdlu-verify`를 거치지 **않는다**. 피드에서 **가져온** manifest만이 검증된다.
  이로써 서명 키를 CI 밖에 둔다.

## Fail-closed 보장

- **`validate_plan`은 어떤 fetch나 apply보다 먼저 실행된다.** `do_diff`에서 fail-closed로, 어떤 `path`든
  절대 경로이거나, `..` 또는 `.` 세그먼트를 포함하거나, `/`로 끝나거나, 제어 문자를 담으면, 또는 어떤
  `sha256`이든 `^[0-9a-f]{64}$`가 아니면, 또는 어떤 `mode`/`class`/`enc`든 유효하지 않으면 **전체**
  manifest를 거부한다. 어떤 적대적 필드도 셸에 도달하지 않으며, `cmd_check`는 어떤 `system()` 보간도
  담지 않는다.
- **경로 봉쇄.** 모든 쓰기와 삭제는 `contained()`를 통해 `MODULE_DIR`에 갇힌다 - apply, delete, 그리고
  reboot `stage_file` 모두 같은 가드를 통과한다. 트리 안의 심볼릭 링크는 프로듀서가 건너뛴다 (트리 밖의
  내용을 결코 유출하지 않음).
- **두 profiles, 반전에 의한 fail-closed.** `trusted` (사설, SSH로 스테이징된 소스)는 best-effort 검증으로의
  **유일한** opt-in이다. **그 밖의** 어떤 값이든 - 오타, 끝의 공백/CR, 또는 다른 대소문자를 포함하여 -
  `hardened`로 취급되며, 거기서는 유효한 서명이 **필수**이고 실패는 중단시킨다. 모든 blob의 `sha256`은
  두 profiles 모두에서 검사된다.
- **어떤 도구 실행보다 먼저 서명 + 해시.** 가져온 정적 `curl`은 root로 실행되므로, `install-tool`은 도구가
  설치되고 실행되기 **전에** tools-manifest 서명 (ed25519-mini, **어떤** profile에서도 필수)과 curl의
  해시를 검증한다 - 실행 전 서명 + 해시가 RCE를 막는다.
- **재개 가능한, 고정 안전 트랜잭션.** 진행 중인 manifest는 `target.json`에 고정된다. 크래시, 네트워크
  손실, 또는 reboot는 plan을 다시 결정하지 않고 저널에서 재개한다. 다운그레이드는 차단되고 (단조
  `version`), 서명된 `module` 필드는 반드시 `MODID`와 같아야 하며, `delete[]`는 오직 `finalize_done`에서만
  실행된다 (`PENDING_REBOOT`는 아무것도 삭제하지 않음). 전체 재해시 없이는 그 무엇도 결코 "완료"가 아니며,
  먼저 `rollback/<v>/` 백업 없이는 그 무엇도 덮어써지지 않는다.

## 하드닝 (심층 방어)

- **크기 상한.** manifest, tools-manifest, 그리고 curl 없는 `wget`/`head -c` 다운로드 경로는 모두 읽히기
  전에 한계가 지어진다 (anti-OOM / anti-flood). blob은 3회 시도 후 자신의 단계에서 실패한다.
- **Check 시점 락.** `check`는 자신의 작업 디렉터리를 재구축하기 전에 mkdir-lock을 획득하므로, 동시 실행이
  그것과 경합할 수 없다.
- **스테이징 봉쇄.** `stage_file`은 라이브 apply 원시 요소들과 같은 `contained()` 가드를 가지므로,
  스테이징된 reboot-hard 경로도 `MODULE_DIR`를 벗어날 수 없다.
- **TLS는 심층 방어이지 신뢰 루트가 아니다.** 정적 curl은 Android 신뢰 저장소 (`--capath`, `ca_path`
  오버라이드)와 함께 mbedTLS를 사용한다. 무결성 보장은 ed25519 서명이며, 인증서 검사는 두 번째 레이어다.

## 참고

- [`INTERFACES.md`](INTERFACES.md) - 불변의 seam 계약 (§5 config, §6 서명, §11 toolchain).
- [`ENGINE.md`](ENGINE.md) - 기기 측 엔진과 그 상태 기계.
- [`PRODUCER.md`](PRODUCER.md) - 패킹, 서명, 정규화, 그리고 키 로테이션.
- 위키: **Security-and-Trust-Model**.

<!-- doc-footer -->

---

> _이 문서는 Claude (Anthropic)로 생성되었으며 VD171이 유지 관리합니다. 수정 및 개선을 환영합니다. [CONTRIBUTING.md](CONTRIBUTING.md)를 참조하세요._
