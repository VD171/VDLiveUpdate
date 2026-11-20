# Architecture

VDLU는 가운데의 한 가지로 이어진 두 측면을 가집니다. PC에서는 [[Producer]]가 모듈 트리를 서명된 콘텐츠 주소화 피드로 바꿉니다. 기기에서는 [[Engine]]이 그 피드를 읽어 무엇이 바뀌었는지 알아내고 적용합니다. 둘 사이의 이음새는 **서명된 매니페스트 + 블롭 저장소**([[Feed Format]])입니다. 그 외에는 아무것도 틈을 건너지 않습니다.

```
        PC / release host                                device
  +--------------------------+                 +---------------------------+
  |  Producer                |                 |  Engine  (update.sh)      |
  |  vdlu-pack  -> manifest  |    signed       |  POSIX sh, no jq          |
  |  vdlu-sign  -> sig       |    feed         |  DIFF FETCH APPLY COMMIT  |
  |  vdlu-gc    -> prune     | =============>  |  journal + rollback       |
  +--------------------------+   manifest.json |  ed25519-mini verify      |
                                 blobs/<sha>   +-------------+-------------+
                                                             |
                                                       +-----v------+
                                                       |  WebUI     |
                                                       |  Updates   |
                                                       |  panel     |
                                                       +------------+
```

두 측면은 절대 런타임을 공유하지 않습니다. Producer는 `python3`와 `openssl`을 사용하고, Engine은 toybox와 내장 `ed25519-mini`를 갖춘 순수 POSIX `sh`입니다. 둘이 합의하는 것은 오직 양쪽 모두가 매니페스트에서 **같은 정규 바이트(canonical bytes)**를 도출하기 때문입니다([[Security and Trust Model]] 참조). WebUI는 루트 관리자 브리지를 통해 엔진을 구동하고 그 진행 저널을 읽는 얇은 바닐라 JS 패널로, 자체적인 업데이트 로직은 전혀 없습니다. [[WebUI]] 참조.

## 두 측면

| 측면 | 실행 위치 | 구성 | 역할 |
|---|---|---|---|
| [[Producer]] | PC / CI | `python3` + `sh` + `openssl` | 모듈 트리를 `manifest.json` + `blobs/`로 순회하고, 서명하고, 고아 블롭을 정리 |
| [[Engine]] | device | POSIX `sh` + toybox + `ed25519-mini` | 설치된 트리를 피드와 비교, 차이를 가져와 적용, 커밋 |
| [[WebUI]] | device (webview) | vanilla JS/CSS | 업데이트 트리거, 진행 표시, 설정 편집, 재부팅 배너 표시 |

## 업데이트 파이프라인

모든 업데이트는 고정된 순서로 실행되는 하나의 트랜잭션입니다:

```
  DIFF  ------>  FETCH  ------>  APPLY  ------>  COMMIT
  read feed      download        write live     re-hash all,
  + validate     only missing    files now,      promote target
  + plan         blobs, verify   stage reboot     -> current,
  (no changes)   each sha256     ones             DONE or
                                                  PENDING_REBOOT
```

- **DIFF**(`update.sh check`이 이 단계이며 읽기 전용). 엔진은 매니페스트만 다운로드하고, 무엇이든 건드리기 **전에** 모든 필드에 대해 `validate_plan()`을 실행한 다음, 피드를 `current.json`과 비교해 파일별 계획을 세웁니다. 디스크의 어떤 것도 바꾸지 않습니다. 피드보다 앞서 있는 기기는 오류가 아니라 무해한 "ahead" 결과입니다.
- **FETCH.** 계획에서 누락된 블롭만 `<sha>.part`로 다운로드하고, `gz`를 압축 해제하고, `sha256sum`을 매니페스트와 대조하고, 검증된 각 블롭을 원자적으로 캐시에 `mv`합니다. 이미 캐시된(또는 변경되지 않은 로컬 파일로 seed된) 블롭은 건너뛰므로, 되돌리기나 공유 파일은 비용이 들지 않습니다. 하나의 블롭에 세 번 실패하면 아무것도 적용하지 않고 단계를 중단합니다. 네트워크 정책에 의해 차단된 다운로드는 오류가 아니라 `DEFERRED`(재개 가능)로 종료됩니다.
- **APPLY.** 일반(`live` / `soft`) 파일은 지금 기록됩니다: `rollback/<v>/`에 백업하고, `.vdlu-tmp`를 쓰고, `chmod`하고, 검증한 다음, 대상 위로 원자적 `rename`을 합니다. reboot 클래스 파일은 `staged/<path>.vdlu-new`로 구체화되고 라이브 inode는 그대로 둡니다. `delete[]` 항목은 백업된 다음 제거됩니다. 모든 단계는 멱등적입니다: 이미 대상 해시인 파일은 건너뜁니다.
- **COMMIT.** 모든 라이브 파일을 재해시합니다. 모든 것이 일치할 때만 엔진은 `target.json`을 `current.json`으로 승격합니다. 스테이징된 것이 있었다면 트랜잭션은 `PENDING_REBOOT`로 끝나고, 그렇지 않으면 `DONE`입니다.

## 콘텐츠 주소화 매니페스트와 블롭

피드는 콘텐츠 주소화되어 있습니다: 매니페스트는 **완전한** 대상 트리를 나열하며 각 파일은 그 `sha256`으로 실려 있고, 블롭 저장소는 서로 다른 각 콘텐츠의 사본 하나를 `blobs/<sha256>`(또는 `blobs/<sha256>.gz`) 아래에 보관합니다.

- **중복 제거.** 트리 안 어디든, 또는 릴리스 전반에 걸쳐 동일한 콘텐츠는 하나의 블롭입니다. 게시는 증분적입니다: `sha256`이 이미 호스트에 존재하는 블롭은 절대 다시 푸시되지 않고, 기기는 이미 가진 콘텐츠를 절대 다시 가져오지 않습니다.
- **sha256은 원본의 것.** 해시는 항상 압축되지 않은 콘텐츠를 가리킵니다. `enc`(`raw` 또는 `gz`)는 그 하나의 블롭이 어떻게 저장되었는지만 기록합니다. 기기는 toybox `gunzip`으로 `gz`를 압축 해제하므로 추가 압축기를 번들로 넣지 않습니다.
- **flavor 안정성.** 기기가 실제로 설치되어 있는 것과 비교하므로, 피드는 모듈 제품군 전체를 실을 수 있습니다. 각 설치는 자신의 flavor를 완성하는 블롭만 가져옵니다.

필드별 전체 레이아웃은 [[Feed Format]]에 있습니다.

## 재개 가능한 저널

모든 트랜잭션은 그 진행 상황이 저널(`journal.json`)에 담겨 있고 진행 중인 트랜잭션의 고정된 대상이 `target.json`에 있기 때문에 크래시에 안전합니다. 상태 기계는 고정된 순서로 실행됩니다:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> ( PENDING_REBOOT | DONE )
                                                               \-> ERROR / DEFERRED
```

| 상태 | 의미 |
|---|---|
| `PLANNED` | 계획이 세워졌고, 아직 아무것도 가져오지 않음 |
| `FETCHING` / `FETCHED` | 블롭 다운로드 중 / 모든 블롭이 존재하고 검증됨 |
| `APPLYING` / `APPLIED_LIVE` | 파일 기록 중 / 모든 라이브 파일 기록됨 |
| `PENDING_REBOOT` | reboot 클래스 파일이 스테이징되어 부팅 교체를 기다림 |
| `DONE` | 모든 것의 재해시가 일치함, `current.json` 승격됨 |
| `ERROR` | 치명적 실패, 모듈은 손상되지 않고 라이브 파일은 `rollback/`에서 되돌려짐 |
| `DEFERRED` | 네트워크 정책에 의해 다운로드가 보류됨, 계획은 유지되고 나중에 재개됨 |

`DONE`은 모든 것의 재해시가 일치해야만 **비로소** 도달하므로, 저널은 절반만 적용된 업데이트가 완료되었다고 절대 주장하지 않습니다. 크래시, 끊긴 네트워크, 또는 도중의 재부팅은 재개 가능한 저널을 남깁니다. `update.sh resume`(또는 `boot`)이 현재 단계에서 이어 받습니다. 명령어 집합과 기기 내 상태 파일에 대해서는 [[Engine]]을 참조하세요.

## 원자성과 롤백

어떤 것도 제자리에서 덮어쓰이지 않고 어떤 것도 잃어버리지 않습니다:

- **원자적 쓰기.** 각 파일은 임시 파일(`.vdlu-tmp`)과 원자적 `rename` / `mv`를 거쳐 안착하므로, 읽는 쪽은 절반만 쓰인 파일을 절대 보지 않습니다.
- **덮어쓰기 전 백업.** 새 파일이 위에 rename되기 전에 이전 콘텐츠가 `rollback/<version>/<path>`로 들어갑니다(최근 몇 개 버전이 보관됨). 적용이 실패하면 라이브 파일은 손상된 채 남겨지는 대신 롤백 사본에서 되돌려집니다. 백업 실패는 안전망 없이 덮어쓰는 대신 적용을 **중단**합니다.
- **직렬화.** `mkdir` 기반 잠금(`lock.d/`, toybox에서 `flock`은 쓸 수 없으므로, PID로 오래된 잠금 복구)이 동시 실행을 직렬화합니다.

## 재부팅 없음 원칙

대부분의 파일은 모듈이 라이브인 상태에서 교체할 수 있으므로 VDLU는 즉시 적용합니다. 재부팅이 필요한 것은 세 가지 클래스뿐인데, 라이브 프로세스가 이미 그것들을 매핑했기 때문입니다: `.so`(Zygisk가 로드), `/system` 오버레이, `sepolicy.rule`. 이것들은 **스테이징되며, 라이브 inode 위로 절대 기록되지 않고**, 다음 부팅에서 단일 pre-zygote 단계에 교체됩니다. 전체 분류 체계와 부팅 흐름은 [[Reboot Handling]]에 있습니다.

## fail-closed 신뢰 자세

피드는 PC에서 기기로 건너오는 유일한 것이므로, 엔진은 그 모든 바이트를 적대적으로 취급합니다. `validate_plan()`은 어떤 다운로드보다 앞선 DIFF 단계에서 실행되며, 잘못된 필드가 하나라도 있으면 매니페스트 전체를 거부합니다. 서명 검증은 내장 `ed25519-mini`를 사용하고(기기에 `openssl` 없음), 개인 키는 기기나 CI에 절대 닿지 않으며, `hardened` 프로필은 반전에 의해 fail-closed라서 손상된 프로필 값이 서명되지 않은 피드를 조용히 수용하는 일은 결코 없습니다. 전체 모델, 두 프로필, 그리고 각각이 답하는 위협은 [[Security and Trust Model]]에 있습니다.
