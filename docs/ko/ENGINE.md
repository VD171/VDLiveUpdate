> **Languages:** [English](../ENGINE.md) · [العربية](../ar/ENGINE.md) · [Čeština](../cs/ENGINE.md) · [Deutsch](../de/ENGINE.md) · [Español](../es/ENGINE.md) · [فارسی](../fa/ENGINE.md) · [Français](../fr/ENGINE.md) · [हिन्दी](../hi/ENGINE.md) · [Bahasa Indonesia](../id/ENGINE.md) · [Italiano](../it/ENGINE.md) · [日本語](../ja/ENGINE.md) · 한국어 · [Nederlands](../nl/ENGINE.md) · [Polski](../pl/ENGINE.md) · [Português](../pt/ENGINE.md) · [Русский](../ru/ENGINE.md) · [Svenska](../sv/ENGINE.md) · [ไทย](../th/ENGINE.md) · [Türkçe](../tr/ENGINE.md) · [Українська](../uk/ENGINE.md) · [Tiếng Việt](../vi/ENGINE.md) · [中文](../zh/ENGINE.md)

---

# VDLU 엔진 (`update.sh`)

KSU/Magisk 모듈을 위한 flashless, 증분 업데이트 클라이언트. `DIFF -> FETCH -> APPLY -> COMMIT`
사이클을 재개 가능한 트랜잭션으로 구현한다. `INTERFACES.md` (수렴의 법칙)를 따른다.

순수 POSIX sh (mksh/busybox/toybox). **SLIM:** toybox (`sha256sum`/`gzip`/`base64`/`date`) +
내장 `ed25519-mini` (ed25519 검증. **기기에 openssl 없음**) + 첫 https 업데이트 때 **가져오는** 정적
`curl` (WebUI가 `fetch()`를 수행하고, Tier-2에 지속시키며, `install-tool`이 사용 **전에** 그 서명+해시를
검증함) 에만 의존한다. `file://`은 curl이 필요 없다. `jq`에 대한 의존 제로.

## 호출

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = ok. `rc != 0` = 에러 (이유는 stderr에). `vdlu-verify`는 다른 컴포넌트가 제공한다
(서명은 `INTERFACES.md §6`). 엔진은 그것을 호출만 한다.

| cmd | 동작 |
|---|---|
| `check` | 읽기 전용 DIFF. `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`을 출력한다. 아무것도 바꾸지 않는다 |
| `run` | 전체 LIVE 사이클 + REBOOT-hard 스테이징. `cancel`을 존중한다. 진행 상황은 `journal.json`에 |
| `resume` | 대기 중인 트랜잭션 (`target.json`)을 현재 단계부터 재개한다. 멱등. `.so`는 swap **하지 않음** |
| `boot` | pre-zygote 모드: resume **+** `staged/*.vdlu-new`를 swap함 → `PENDING_REBOOT`→`DONE`을 닫는다. 대기 중인 트랜잭션이 없으면 새 사이클을 실행하여 모든 것 (`.so` 포함)을 한 번의 boot에 적용한다 |
| `status` | `journal.json`을 출력한다 (없으면 `{"state":"idle"}`) |
| `cancel` | `$VDLU_DIR/cancel`을 생성한다. 진행 중인 `run`은 다음 안전 지점에서 멈춘다 |

## 상태 기계 (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE`은 **모든 것**의 재해시가 일치할 때만. REBOOT-hard가 스테이징되었으면 ⇒ `PENDING_REBOOT` (결코 거짓
`DONE`이 아님). 어떤 실패에서도 `ERROR`. 단 모듈은 손상시키지 않는다 (적용된 LIVE 파일은 `rollback/<v>/`에서
되돌려진다. "반쯤 적용해놓고 거짓말하는" 것 없음). `fetch` 단계의 양성 출구: **`DEFERRED`** -
`net_policy`가 다운로드를 연기함 (네트워크 비허용). plan/target은 유지되며 다음 check/boot에서 재개한다
(WebUI는 에러가 아니라 파란 정보 토스트 "waiting for X network"를 표시함).

## 엄격성 보장

- **FETCH:** `net_policy`로 게이트됨 (any/wifi/mobile. http/https만, `file://`은 절대 대상 아님). 비허용
  네트워크 ⇒ 데이터를 쓰지 않고 `DEFERRED` (재개 가능). 없는 것만 `<sha>.part`로 다운로드하고 (curl은
  `--connect-timeout` + `--speed-time`로, 결코 멈추지 않음), `gz`를 압축 해제하고 (toybox `gunzip`), `sha256sum` ==
  manifest를 검사하고, 원자적 `mv`로 `blobs/<sha>`로. 캐시됨+ok인 blob은 건너뜀. 변경되지 않은
  로컬 파일에서 blob을 seed할 수 있다 (dedup/오프라인). **같은 blob에서 3회 실패 = 단계가 아무것도 적용하지 않고 중단된다.**
  plan의 모든 blob이 존재+검증되어야만 `FETCHED`가 된다. 툴체인 설정 시, 해결된 TLS 신뢰 (CA 경로 +
  가독성, 번들 크기와 인증서 수)를 로그에 남기므로 boot 시점의 curl `rc 77`은 `boot.log`에서 자기 설명적이
  된다 - 빈 저장소와 읽을 수 없는 저장소 (boot의 SELinux 컨텍스트 경우)를 구별한다.
- **APPLY** (`FETCHED`에서만): `live`/`soft` → `rollback/<v>/`에 백업 → `.vdlu-tmp` → `chmod` → 검증 →
  원자적 `rename`. `reboot` → `staged/<path>.vdlu-new`로 실체화한다 (라이브 inode는 건드리지 않음).
  `delete[]` → 백업 → 제거. 멱등 (이미 타겟 해시인 파일은 건너뜀).
- **COMMIT:** 모든 `live`/`soft`의 재해시. 그 뒤에야 `current.json`을 쓴다. 스테이징된 파일이 있으면 ⇒
  `PENDING_REBOOT`. `boot`은 `mv -f staged/....vdlu-new $MODULE_DIR/<path>` (pre-zygote) + 재검증 +
  `DONE`을 수행한다.
- **cancel:** 파일들 사이 (안전 지점)에서 확인됨. 진행 중인 `.vdlu-tmp`/`.part`를 제거하고, `cancel`을 지우며,
  journal을 재개 가능한 상태 (`cancelled:true`, `error:null`)로 남긴다.
- **mkdir-lock `$VDLU_DIR/lock.d`**가 직렬화한다 (flock은 toybox에서 동작 불가. stale 복구는 PID로). 
  인내심 있는 boot-retry는 대기 중에 락을 보유하지 않고 (`acquire_lock_try`+release를 시도 사이에 함) wakelock도
  없다 - 배터리 안전. 중간의 크래시/네트워크/reboot → `resume`/`boot`이 계속한다.
- **profile=hardened** ⇒ 사용 **전에** manifest에 대한 `vdlu-verify` 필수. 실패 = 중단. 다운그레이드 차단
  (단조 버전). **trusted** ⇒ 검증은 best-effort이지만, 모든 blob의 해시는 **항상** 검사된다.
- **module-update 키 allowlist (두 profiles 모두):** `verify_manifest`는 `key_id`가 구성된 `key_id` allowlist (INTERFACES §5/§6 참조)에 없는 manifest를 pubkey가 선택되기 전에 fail-closed로 거부한다. 따라서 단지 keyring에 들어 있을 뿐인 신뢰도가 낮은 키 (예: fingerprint-feed 키)는 결코 flashless root 업데이트에 서명할 수 없다. 미설정 시 기본 안전: 단일 키 keyring = 그 하나의 키만, 다중 키 keyring = `key_id`가 고정될 때까지 거부.
- **신뢰 앵커 제외 (VDLU#2):** 엔진은 가져온 plan 안의 모든 `vdlu/` 경로 (`update.sh`, `vdlu-verify`, `verify/*`, `keyring/*`, config)를 **무시한다** - 서명된 피드가 그것들을 담고 있어도 결코 가져오거나, 적용하거나, 삭제하지 않는다. 피드는 결코 기기 상의 verifier나 서명 키를 교체할 수 없으며, 신뢰 앵커는 완전한 서명된 재플래시로만 바뀌므로, 유출된 단일 서명 키가 유선으로 root를 지속시킬 수 없다.
- **비지 지연 (옵트인 `apply_busy_file`):** `apply_busy_file`이 설정되면 (호스트 모듈이 자신의 작업 중에 touch하는 절대 경로, 예: 실행 중인 백업), 그 경로가 존재하는 동안 APPLY가 지연된다 - 업데이트가 작업 도중에 모듈 파일을 교체하는 일은 결코 없다. blob은 이미 가져와 있으므로, 다음 트리거는 재다운로드 없이 적용한다.
- **크기 상한:** 파일당 128 MiB (`MAX_FILE_BYTES`)와 manifest당 2 MiB (`MAX_MANIFEST_BYTES`)로, `update.sh`와 `vdlu-verify` 양쪽 모두에서 읽기 전에 강제된다 (anti 압축 해제 폭탄 / anti-OOM).
- 우아하게 저하됨: 바이너리 누락 / 네트워크 끊김 / 디스크 가득 → stderr에 명확한 에러 + journal의 `state:ERROR`.
  모듈은 손상시키지 않음.

## jq 없는 JSON 파싱

`awk` 기반 gron 스타일 평탄화기 (순수 POSIX: `substr`/`index`/`gsub`/`split`/`printf` + 파라미터로 전달되는
로컬 변수)가 manifest를 문자 단위로 토큰화하여, 스칼라 리프마다 한 줄의 `path<TAB>value`를 방출한다
(`files/0/sha256<TAB>ab..`, `version<TAB>6`, `delete/0<TAB>etc/x`). 컴팩트 **또는** 예쁘게 출력된
JSON에 대해 견고함. `sh`는 `grep`/`cut`로 그것을 소비한다. 파일별 plan은 두 번째 `awk`에서 TSV
(`class st mode enc sha size path`)로 재구성되어 `$VDLU_DIR/plan.tsv`가 된다.

## 상태 파일 (`$VDLU_DIR` 내, Tier-2)

| 파일 | 역할 |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`key_id`/`apply_busy_file`/`boot_retry_*`/…. INTERFACES §5 참조) |
| `current.json` | ACTIVE 버전의 manifest (diff 기준). 부재 = 한 번도 업데이트 안 됨 |
| `target.json` | 진행 중 트랜잭션의 고정된 manifest (존재 = 활성 트랜잭션). `DONE`에서 `current.json`이 됨 |
| `plan.tsv` / `plan.del` | plan + 파일별 진행 (st) / 삭제할 경로 |
| `journal.json` | WebUI용 진행 상황 (각 전이마다 재생성됨) |
| `blobs/<sha256>` | 검증된 원본 내용의 캐시 |
| `rollback/<version>/<path>` | 덮어쓴 파일의 백업 (undo. 마지막 3개를 보관함) |
| `staged/<path>.vdlu-new` | boot에서의 swap을 기다리는 REBOOT-hard |
| `lock.d/` | mkdir-lock (flock은 toybox에서 동작 불가. stale 복구는 PID로) |
| `tools/<abi>/curl` | 가져온 정적 curl (슬림 부트스트랩). 업데이트를 가로질러 지속됨 |
| `cancel` | 취소 요청 |

<!-- doc-footer -->

---

> _이 문서는 Claude (Anthropic)로 생성되었으며 VD171이 유지 관리합니다. 수정 및 개선을 환영합니다. [CONTRIBUTING.md](CONTRIBUTING.md)를 참조하세요._
