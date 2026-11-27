> **Languages:** [English](../AI-AGENTS.md) · [العربية](../ar/AI-AGENTS.md) · [Čeština](../cs/AI-AGENTS.md) · [Deutsch](../de/AI-AGENTS.md) · [Español](../es/AI-AGENTS.md) · [فارسی](../fa/AI-AGENTS.md) · [Français](../fr/AI-AGENTS.md) · [हिन्दी](../hi/AI-AGENTS.md) · [Bahasa Indonesia](../id/AI-AGENTS.md) · [Italiano](../it/AI-AGENTS.md) · [日本語](../ja/AI-AGENTS.md) · 한국어 · [Nederlands](../nl/AI-AGENTS.md) · [Polski](../pl/AI-AGENTS.md) · [Português](../pt/AI-AGENTS.md) · [Русский](../ru/AI-AGENTS.md) · [Svenska](../sv/AI-AGENTS.md) · [ไทย](../th/AI-AGENTS.md) · [Türkçe](../tr/AI-AGENTS.md) · [Українська](../uk/AI-AGENTS.md) · [Tiếng Việt](../vi/AI-AGENTS.md) · [中文](../zh/AI-AGENTS.md)

---

# AI 에이전트에서 VDLU 구동하기

VDLiveUpdate(VDLU)는 KSU/Magisk 모듈이 `vdlu/`에 벤더링하는 플래시 없는 증분 업데이터입니다. 엔진 전체가 셸에서 구동되므로, AI 어시스턴트나 에이전트가 업데이트를 헤드리스로 확인, 적용, 재개, 완료할 수 있습니다. WebUI가 돌리는 것과 같은 사이클이며, UI도 없고 루프 안에 사람도 없습니다. 출력되는 JSON을 파싱하고, 텍스트를 절대 스크래핑하지 마세요.

## 계약

장치에서 root로 실행되는 단일 진입점으로, 엔진의 세 환경 변수를 설정한 채:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <verb>
```

- `VDLU_DIR`은 Tier-2 상태 디렉터리(모듈 바깥, 리플래시에서도 살아남음), `MODULE_DIR`은 모듈의 살아 있는 트리, `MODID`는 모듈 id입니다.
- `rc 0` = 정상, `rc != 0` = 오류, 이유는 stderr에.
- 읽기 동사(`check`, `status`)는 stdout에 **하나의 JSON 객체**를 출력합니다. 그것을 파싱하고, 텍스트를 절대 스크래핑하지 마세요.
- 엔진은 toybox(`sha256sum`/`gzip`/`base64`)와 내장 `ed25519-mini`, 그리고 첫 https 업데이트 때 가져오는 정적 `curl`에만 의존합니다. `jq`는 제로입니다.

개발 중에는 같은 스크립트가 이 저장소의 `engine/update.sh`에 있으므로, 세 변수를 설정한 `sh engine/update.sh <verb>`가 스테이징 사본을 같은 방식으로 구동합니다.

## 동사

| 동사 | 하는 일 | 출력 |
|------|------|--------|
| `check` | 피드에 대한 읽기 전용 DIFF, 아무것도 바꾸지 않음 | `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`, 또는 장치가 피드보다 앞선 경우 `{"update":false,"ahead":true,"from":N,"to":M}`(다운그레이드 차단, 무해, rc 0) |
| `run` | 전체 LIVE 사이클 DIFF -> FETCH -> APPLY -> COMMIT, LIVE 파일을 적용하고 REBOOT-hard를 스테이징, `cancel`을 존중 | 진행 상황은 `journal.json`에 |
| `resume` | 보류 중인 트랜잭션을 현재 단계부터 재개, 멱등, `.so`를 결코 교체하지 않음 | 갱신된 `journal.json` |
| `boot` | pre-zygote 모드, `resume`에 더해 스테이징된 `.so`의 교체, `PENDING_REBOOT`를 `DONE`으로 닫음 | 갱신된 `journal.json` |
| `status` | 읽기 전용 스냅샷, 아무것도 바꾸지 않음 | `journal.json`, 또는 활성 트랜잭션이 없을 때 `{"state":"idle"}` |
| `cancel` | 중지를 요청, 진행 중인 `run`은 다음 안전 지점에서 멈춤 | `$VDLU_DIR/cancel`을 생성 |

헤드리스 업데이트는 보류된 것이 있는지 보려는 `check`, 라이브로 갈 수 있는 모든 것을 적용하는 `run`, 그다음 스테이징된 `.so`를 교체하려는 다음 부팅 시의 `boot`입니다(또는 지연된 페치를 재시도하는 `resume`). 모든 동사는 다시 호출해도 안전하며, 사이클 중간의 충돌이나 네트워크 끊김은 재개 가능한 저널을 남기지, 결코 절반만 적용된 모듈을 남기지 않습니다.

## 상태 JSON

`status`(그리고 `$VDLU_DIR/journal.json`의 살아 있는 파일)는 WebUI와 에이전트가 함께 읽는 진행 계약입니다:

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit",
  "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>,
  "reboot_pending":bool, "cancelled":bool, "error":"<str|null>",
  "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

- `state`는 고정된 순서로 이동합니다: `PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)`.
- `DONE`은 모든 것의 재해시가 일치한 후에만 도달합니다. 스테이징된 REBOOT-hard 파일은 `PENDING_REBOOT`을 내며, 결코 가짜 `DONE`이 아닙니다. 마치려면 `boot`을 실행하세요.
- `DEFERRED`는 `net_policy`가 다운로드를 차단했다는 뜻으로, 무해하고 재개 가능한 상태이지 오류가 아닙니다. 계획은 지속되고 다음 `check`/`boot`이 이어갑니다.
- `ERROR`는 이유를 `error`에 담고, 적용된 LIVE 파일은 `rollback/`에서 되돌려지며, 모듈은 결코 절반만 적용된 채 남지 않습니다.
- `error:null`과 함께 `cancelled:true`는 깨끗한 중지이며, 저널은 재개 가능한 상태로 남습니다.

## 이음새 계약

모든 구성 요소(엔진, 프로듀서, WebUI)는 수렴의 법칙인 [`INTERFACES.md`](INTERFACES.md)를 따릅니다. CLI 동사, `manifest.json` 스키마, `journal.json` 키, 거기 정의된 config 키는 **불변**이므로, 그 파일을 유일한 진실의 원천으로 다루고 그중 어느 것을 바꾸기 전에 거기에 맞추세요. 엔진 내부(재개 가능한 트랜잭션, 엄격성 보장, trust-anchor 제외)는 [`ENGINE.md`](ENGINE.md)를, 피드 쪽(내용 주소 지정 피드의 빌드와 서명)은 [`PRODUCER.md`](PRODUCER.md)를 참조하세요.

## 에이전트를 위한 규칙

- 동사와 JSON을 사용하고, WebUI를 절대 스크래핑하지 말고, 상태 파일을 절대 손으로 편집하지 마세요.
- `INTERFACES.md`를 불변으로 다루세요. 변경은 먼저 계약을 맞추는 것을 뜻합니다.
- AI 에이전트의 패치는 다른 어떤 것과도 같은 리뷰 기준을 통과합니다. build는 늘 release, 아무것도 느슨하게 하지 말고, 아무것도 잃지 마세요.

<!-- doc-footer -->

---

> _이 문서는 Claude (Anthropic)로 생성되었으며 VD171이 유지 관리합니다. 수정 및 개선을 환영합니다. [CONTRIBUTING.md](CONTRIBUTING.md)를 참조하세요._
