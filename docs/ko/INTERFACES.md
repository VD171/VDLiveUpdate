> **Languages:** [English](../INTERFACES.md) · [العربية](../ar/INTERFACES.md) · [Čeština](../cs/INTERFACES.md) · [Deutsch](../de/INTERFACES.md) · [Español](../es/INTERFACES.md) · [فارسی](../fa/INTERFACES.md) · [Français](../fr/INTERFACES.md) · [हिन्दी](../hi/INTERFACES.md) · [Bahasa Indonesia](../id/INTERFACES.md) · [Italiano](../it/INTERFACES.md) · [日本語](../ja/INTERFACES.md) · 한국어 · [Nederlands](../nl/INTERFACES.md) · [Polski](../pl/INTERFACES.md) · [Português](../pt/INTERFACES.md) · [Русский](../ru/INTERFACES.md) · [Svenska](../sv/INTERFACES.md) · [ไทย](../th/INTERFACES.md) · [Türkçe](../tr/INTERFACES.md) · [Українська](../uk/INTERFACES.md) · [Tiếng Việt](../vi/INTERFACES.md) · [中文](../zh/INTERFACES.md)

---

# VDLU - 인터페이스 계약 (컴포넌트 사이의 이음새)

**수렴의 법칙:** 모든 컴포넌트는 이 파일을 따른다. 4개 에이전트가 만든 조각들은 **서로 맞물려야** 한다. 아래의
CLI 시그니처, 파일 이름, JSON 키는 **불변**이다 (변경하려면 먼저 여기에서 정렬할 것).

리포지토리에서 물려받은 원칙: 기기에서는 **순수 POSIX sh** (bashism 없음. toybox/busybox +
toybox의 `sha256sum`/`gzip`/`base64` + 가져온 `curl` + 내장 `ed25519-mini`로 동작한다. 슬림하며, 바이너리
번들 없음), **불필요한 주석 제로**, **항상 릴리스**, **실패 시 엄격함** (재개 가능한 트랜잭션, 거짓으로 "완료"된
것 없음, 잃는 것 없음), **아무것도 느슨하게 하지 않음**.

---

## 1. 상태 레이아웃 (Tier-2, 모듈 디렉터리 밖)

```
$VDLU_DIR = /data/adb/<module>/vdlu
  config               # key=value (§5)
  current.json         # manifest of the ACTIVE version (diff base); absent = never updated
  journal.json         # transaction in progress (§4); absent = idle
  cancel               # presence = cancel request (WebUI creates it; engine deletes it on stop)
  lock.d/              # mkdir-lock (flock unworkable on toybox; stale-recovery by PID)
  blobs/<sha256>       # cache of verified blobs (ORIGINAL content, already decompressed)
  rollback/<version>/<path>   # backup of overwritten files
  staged/<path>.vdlu-new      # REBOOT-hard awaiting swap at boot
  target.json          # PINNED manifest of the in-flight transaction (presence = active transaction; becomes current.json on DONE)
  plan.tsv  plan.del   # engine's internal plan (progress); the WebUI IGNORES it (reads only journal/config/current)
```
journal의 `cancelled:true` = 엔진이 취소로 멈춘 상태 (비종단이며 재개 가능한 상태. `error`
는 null로 유지).

모듈에 함께 벤더링되는 엔진: `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`). `$MODULE_DIR =
/data/adb/modules/<module>`. 엔진은 env를 통해 다음을 받는다: `VDLU_DIR`, `MODULE_DIR`, `MODID`.

## 2. 엔진 CLI (ENGINE 컴포넌트)

`sh update.sh <cmd>` - rc 0 = ok, !=0 = 에러 (이유는 stderr에):

| cmd | 동작 |
|---|---|
| `check` | DIFF: manifest를 다운로드하여 비교한다. 한 줄짜리 JSON `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`을 출력한다. 아무것도 바꾸지 않는다. 기기가 피드보다 AHEAD (다운그레이드 차단, 강화됨) = **양성** 상태: `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (결코 "check failed"가 아님). do_diff rc: 2 fetch/parse, 3 verify/meta, 4 ahead |
| `run` | 전체 사이클: DIFF→FETCH→APPLY→COMMIT. `cancel`을 존중한다. 진행 상황을 `journal.json`에 기록한다. LIVE를 적용하고 REBOOT-hard를 스테이징한다 |
| `resume` | `journal.json` 트랜잭션을 현재 단계부터 재개한다 (멱등) |
| `boot` | pre-zygote 모드: `resume` + `staged/*.vdlu-new`의 SWAP을 수행한다 (`.so` 적용), `PENDING_REBOOT`→`DONE`을 닫는다 |
| `status` | `journal.json`을 출력한다 (없으면 `{"state":"idle"}`) |
| `cancel` | `$VDLU_DIR/cancel`을 생성한다 (진행 중인 `run`은 다음 안전 지점에서 멈춘다) |

Blob/manifest 소스: config의 `source`. `<source>` + `/manifest.json`, `/blobs/<sha>`, `/blobs/<sha>.gz`.
`source`는 `https://` (정적 curl로 가져옴, TLS) 또는 `file://` (로컬 스테이징)로 시작한다.

## 3. manifest.json (PRODUCER가 생성, ENGINE이 소비)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":3, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = 완전한 타겟 트리. `class`: `live` (webroot/bin/lib/confs/scripts-on-demand/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`, `system/**`, `*.rule`).
  경로 기반 기본값. `reboot`→`live`로 결코 다운그레이드하지 않는다.
- `enc`: `gz` (gzip `-9 -n`, 결정론적. 기기에서는 toybox gunzip)는 압축이 잘 되고 **또한**
  크기가 유의미할 때만. `sha256`은 **항상** 원본 내용에 대한 것.
- `sig`: `sig` 필드를 제외한 정규 manifest의 서명 (verify의 §4).

## 4. journal.json (ENGINE이 기록, WEBUI가 읽음 - 진행 계약)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

상태 기계 (고정 순서): `PLANNED→FETCHING→FETCHED→APPLYING→APPLIED_LIVE→(PENDING_REBOOT|DONE)`.
`DONE`은 **모든 것**의 재해시가 일치할 때만. 스테이징된 REBOOT-hard ⇒ `PENDING_REBOOT` (`DONE`이 아님).
`fetch` 단계에서의 출구: `ERROR` (하드 실패) 또는 `DEFERRED` (net_policy가 다운로드를 차단함 - 양성/재개 가능,
에러 아님).

## 5. config (key=value, 한 줄에 하나. WEBUI에서 편집 가능)

```
auto_on_webui_open=0
auto_on_reboot=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=trusted        # trusted | hardened. CODE DEFAULT (line absent) = hardened (fail-closed, 9a9a824)
net_policy=any         # any (Wi-Fi+mobile) | wifi (Wi-Fi only) | mobile (mobile only) - gates the DOWNLOAD by network type
allow_metered=0        # ⚠️ SUPERSEDED by net_policy (not consumed by the engine)
pubkey_dir=keyring     # relative to $MODULE_DIR/vdlu (keyring of pubkeys for verify)
key_id=                # ALLOWLIST of accepted MODULE-UPDATE signing key id(s), comma-separated (rotation).
                       # UNSET = default-safe: a single-key keyring accepts only that one key; a MULTI-key
                       # keyring (one that also ships a fingerprint-feed key) MUST pin its module key here.
ca_path=               # empty = auto-detect of the Android trust store; set a path to override
tools_source=          # empty = derived from source (.../vdlu-tools); feed of the static curl
boot_retry_interval=30 # seconds between probes when BOOT finds the device offline (floor 5s)
boot_retry_minutes=0   # ceiling of the PATIENT retry (AWAKE-time) only at boot; 0 = off. Battery-safe (no wakelock,
                       # no held lock, route probe never wakes the radio) -> a generous ceiling is ~free
```

**Boot retry (오프라인) - 인내심 있고 배터리 안전:** `boot`에서만 (check/auto-open에서는 결코 안 함). manifest
가져오기가 네트워크 때문에 실패하면 (`fetch_offline`이 fetcher의 종료 코드로 분류), 성공하거나
`boot_retry_minutes`만큼의 AWAKE 시간이 소진될 때까지 기다렸다가 재시도한다. **아무것도 붙잡지 않고 소모시키지 않는** 설계:
- **wakelock 제로:** 시도 사이에는 `sleep`이며, deep-sleep에서 동결된다 → 기기는 정상적으로 잔다
  (배터리 ~제로). 재시도는 일시 정지했다가 기기가 이미 깨어난 뒤에 재개한다.
- **보유 락 제로:** 시도 **사이**에 `acquire_lock_try`+release (대기 중에 락을 보유하지 않음) →
  `run`/수동 check는 결코 막히지 않는다. 그 사이에 수동 run이 TARGET을 스테이징하면 boot는 양보한다.
- **쓸데없이 radio를 깨우지 않음:** `net_allowed` 프로브 (`net_type`/`ip route get` 경유, Android의 정책 라우팅을
  존중하는 커널 라우트 조회. 패킷 없음)가 각 시도를 게이트한다 - 네트워크가 나타났을 때만 fetch를 소비한다.
- 결정론적 실패 (manifest/sig/downgrade)는 결코 재시도하지 않는다. fetch에 `--connect-timeout 15` (captive portal에서
  멈추지 않음). `service.sh`가 그것을 백그라운드로 돌린다 (boot은 결코 멈추지 않음).
- ⛔ **HARD: `boot_retry_minutes>0`을 켜려면 인내심 있는 엔진이 필요하다** (
  `net_allowed`+`acquire_lock_try`를 가진 것, 정규 `da7115f4`+). 이전 boot-retry (윈도우 전체 동안 락을 보유하고
  + 오프라인에서 맹목적으로 curl을 재시도함)는 **배터리를 소모시키고/radio를 깨운다** - 오래된 엔진에서 재시도를
  켜는 것은 자충수다. 켤 때는 현재 엔진을 벤더링할 것.

**`net_policy` (any|wifi|mobile):** **다운로드**를 네트워크 유형으로 게이트한다. `net_type()`는
`ip route get`의 egress를 분류한다 (셀룰러 iface `rmnet/ccmni/v4-*/clat` = mobile. 그 외 = wifi. 커널 조회,
패킷 없음). `net_allowed()`는 `net_policy`와 비교하여 `do_fetch` (blobs) + 인내심 있는 boot-retry
프로브를 게이트한다. **manifest check는 무료로 유지된다** (작음 → 어떤 네트워크에서도 UI가 업데이트를 보고함).
다운로드만이 허용된 네트워크를 기다린다. 허용되지 않은 네트워크에서의 다운로드 = journal의 **`DEFERRED`**
상태 (ERROR 아님. 부드러운 파란 INFO 토스트 "waiting for X network". plan/target은 유지되며, 올바른 네트워크에서
다음 check/boot 때 재개됨). `net_policy`는 `allow_metered` (결코 소비된 적 없음)를 **대체한다**.
엔진 `97baf887`+ (`file://`은 결코 게이트되지 않음).

## 6. 서명 (PRODUCER가 PC에서 openssl로 서명, ENGINE이 기기에서 ed25519-mini로 검증)

- 정규화: `sig`를 제외한 manifest, 키 정렬, 컴팩트 JSON (불필요한 공백 없음), UTF-8.
  서명/검증되는 것 = 그 정규형의 `sha256` 16진수 (크로스툴 결정성을 제공함).
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` → `key_id` + `sig` (정규 sha256의 ed25519 서명의 base64)를 manifest에 제자리에서 주입한다.
- `engine/vdlu-verify <manifest.json> <keyring_dir>` → keyring의 `<key_id>.pub` 공개키에 `sig`가 일치하면 rc 0
  (SLIM: 공개키는 **RAW 32 바이트**). 내부적으로 openssl 없음: toybox `sha256sum`/`base64 -d` + 내장
  `ed25519-mini` 바이너리 (CLI `ed25519-mini <pub32> <msg> <sig64>`, rc 0=유효/1=무효/2=사용법).
  rc!=0 = 거부. **`profile=hardened` ⇒ 검증 필수. 실패 = 중단.**
  `profile=trusted` ⇒ 검증은 best-effort (소스는 SSH를 통해 이미 신뢰됨)이지만, 모든 blob의 해시는 **항상** 검사된다.
- **module-update 키 allowlist (fail-closed, pubkey 선택 전):** manifest의 `key_id`는 `<key_id>.pub`가 선택되기 전에 허용된 MODULE-UPDATE 키여야 한다 - config의 `key_id` (§5)가 그 allowlist다. keyring은 신뢰도가 낮은 키도 담을 수 있다 (예: fingerprint-feed 키, 자동화됨, 다른 계정). allowlist가 없으면 그 키로 서명된 manifest는 유출될 경우 검증을 통과하고 완전한 flashless root 업데이트를 적용하게 된다. `verify_manifest`는 두 profiles 모두에서 이를 강제하며, 해결된 집합을 env `VDLU_KEYID_ALLOW`를 통해 `vdlu-verify`에 전달한다 (독립 verifier도 동의하도록). 미설정은 기본 안전 (단일 키 keyring: 그 키만; 다중 키 keyring: `key_id`가 고정될 때까지 거부). fingerprint-feed 신뢰 루트는 자체 고정 키를 가진 별도 경로이며 영향을 받지 않는다.
- `producer/vdlu-keygen <id> <out>` → `<id>.pem` (개인) + `<id>.pub` (PEM, PC의 툴링용) +
  `<id>.pub.raw` (**RAW 32B** = 기기의 슬림 keyring의 `<id>.pub`)을 생성한다. openssl `genpkey -algorithm ed25519`.

## 7. Blob - 검증 (ENGINE)

`<source>/blobs/<sha>` (또는 `enc=gz`면 `.gz`)을 다운로드하여 `.part`에 쓰고, `gz`면 압축 해제하고 (`gunzip`),
`sha256sum` == manifest의 `sha256`을 검사한다. 일치 → 원자적 `mv`로 `$VDLU_DIR/blobs/<sha>`로. 같은 blob에서
3회 실패 = 단계를 중단한다 (아무것도 적용 안 함). `$VDLU_DIR/blobs/<sha>`에 해시가 ok인 blob이 이미 있음 =
다운로드를 건너뛴다.

## 8. 클래스별 APPLY (ENGINE)

- `live`/`soft`: `rollback/<v>/<path>`에 백업 → blob에서 `$MODULE_DIR/<path>.vdlu-tmp`를 씀 → `chmod mode` →
  타겟 위에 원자적 `rename`. 이미 타겟 해시임 = 건너뜀. (Zygisk 변형에서는 쓰기가 마운트된 디렉터리로 감 =
  파일별 병합이며, 디렉터리를 `rm -rf` 하지 않음.)
- `reboot`: `$VDLU_DIR/staged/<path>.vdlu-new`로 실체화한다 (라이브 것은 건드리지 않음). swap은 `boot`에서.
- `delete[]`: 백업 → 제거.

## 9. WEBUI ↔ ENGINE (WEBUI 컴포넌트)

- 실행: `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (백그라운드).
- 진행: 약 1초마다의 가벼운 폴링 `ksu.exec("cat $VDLU_DIR/journal.json")`. `{phase,state,total,done,current,bytes}`를 렌더링한다.
- Liveness: journal이 8틱 부재 ⇒ "no response". journal이 20틱 동안 FROZEN (같은 값) ⇒ `lock.d`를 확인: 살아 있음 = 계속 (blob 1개의 느린 fetch), 죽음 = 에러 + Resume. 이것이 없으면 fetch 중에 죽은 run이 토스트를 "updating"에 얼려버린다.
- Cancel: `ksu.exec("touch $VDLU_DIR/cancel")`.
- Config: "Updates" 탭에서 `$VDLU_DIR/config` (key=value)을 읽고 쓴다.
- Toast: 바 + `phase done/total · current`. `reboot_pending`으로 끝나면 ⇒ 영구 배너 "reboot to activate the .so".
- Auto-open (`auto_on_webui_open=1`): 먼저 QUIET한 `check()`를 수행한다 (진행 토스트 없음). `update && fetch>0`일 때만 `run`+영구 토스트를 실행한다. 최신/ahead/새 것 없음 = 패널 내 인라인 결과, 남는 토스트 제로. 수동 버튼처럼 비침습적 (실제 다운로드가 있을 때만 토스트가 나타남). curl 부트스트랩은 일회성이다.

## 10. 데모로의 통합 (INTEGRATION 컴포넌트) - 스니펫, 라이브 파일은 편집하지 않음

`integration/demo/`에, 스니펫 + 각 스니펫이 들어갈 위치를 적은 `INTEGRATION.md`를 (적용하지 않고) 생성한다:
- `post-fs-data`/`service.sh`의 `auto_on_reboot` 훅 (pre-zygote → `update.sh boot`)과 `auto_on_webui_open`.
- `config` 기본값 + 내장 keyring + 벤더링 (`modules/<mod>/vdlu/`).
- PARTIAL 변형 (마운트된 디렉터리로의 병합).

## 11. 가져오는 툴체인 + 베이스라인 (SLIM, 접근법 B)

**모듈 (zip) 내 레이아웃:** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`. `bin/` (openssl/curl/zstd)는 **없음**. `customize.sh`는 `verify/`를
기기의 ABI까지 쳐낼 수 있다 (`vdlu-verify`는 mini를 `<dir>/ed25519-mini` 또는 `<dir>/verify/<abi>/ed25519-mini`에서 찾음).

**ed25519-mini** (내장 바이너리, 검증 전용): `ed25519-mini <pubkey32> <msg> <sig64>` → rc 0=유효,
1=무효, 2=사용법/IO. msg = 서명된 정확한 바이트 (재해시하지 않음). TweetNaCl PD, ABI별 정적, PROVENANCE.

**tools-feed** (public/https 프로파일 전용): `<tools_source>`에서 제공됨 (기본 파생: `source`의 마지막
세그먼트를 `vdlu-tools`로 교체. 예 `https://<user>.github.io/<repo>/vdlu-tools`). 내용:
- `tools-manifest.json` - `<abi>/curl` 트리에 대한 서명된 `vdlu-pack` manifest. 각 curl의 `sha256`을
  고정한다 (같은 `release-2026` 키).
- `<abi>/curl` - RAW **정적** curl (자체 완결, ~1MB. curl 8.11.1 + mbedTLS). 🪤 mbedTLS는
  CA 번들을 가지고 있지 않다: `fetch_url`은 `--capath`을 전달한다 (Android 신뢰 저장소 자동 감지: `/system/etc/security/cacerts`
  → APEX conscrypt. `ca_path`로 재정의). capath 없음 = 에러 60. 무결성은 ed25519이고, cert 검사는 심층 방어다.

**install-tool** (ENGINE): `update.sh install-tool <abi>`는 `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}`
을 읽고 (WEBUI가 `fetch()`로 다운로드하여 거기에 씀), **tools-manifest 서명을 검증하고 (ed25519-mini,
어떤 프로파일에서도 필수)** + curl의 해시 == manifest를 검증한 뒤에야 `$VDLU_DIR/tools/<abi>/curl` (0755)에 설치한다.
curl은 root로 실행됨 → exec 전의 sig+hash가 RCE를 막는다. Tier-2에 지속됨: 재다운로드되지 않음 (언인스톨 시 제외).

**fetch-bootstrap** (WEBUI, `ensureToolchain()`): check/run/resume 전에 실행된다. `file://` = no-op. curl이 **이미**
사용 가능 (Tier-2, 또는 **자체 번들** 모듈의 `module/bin/<abi>/curl`, 또는 시스템) = no-op
(VDLU는 기존 curl을 재사용함). curl이 **전혀 없는** `https`일 때만 webview를 통해 curl + tools-manifest를 다운로드하여,
그것들을 `.work`에 쓰고 (`ksu.exec` 경유 청크 base64), `install-tool`을 호출한다. 신뢰 = 다운로드가 아니라 기기에서의 검사.

> 🪤 **슬림 (fetch-bootstrap) ≠ 필수.** **자신의** 기능을 위해 `bin/`이 존재하는 모듈 (예: 
> restic/rclone/age/tar/curl... 을 번들함)은 ~2MB로 슬림해지지도, curl을 다운로드하지도 않는다 - VDLU는 슬림 엔진
> (gz, mini, baseline, 수정들)을 채택하고 내장 툴체인을 **재사용**한다. 자체 툴체인이 없는 모듈
> 만이 ~2MB를 얻는다.

**baseline.json** (from:0 수정): 릴리스는 출시 버전의 서명된 `manifest.json`을
`vdlu/baseline.json`으로 복사한다. 새로 설치할 때 엔진은 그것으로부터 `current.json`을 seed한다 (`init_paths`, 부재할 때만) → 
기기는 "current"로 태어나며, 자기 자신의 자동 업데이트도 재가져오기도 없다.

<!-- doc-footer -->

---

> _이 문서는 Claude (Anthropic)로 생성되었으며 VD171이 유지 관리합니다. 수정 및 개선을 환영합니다. [CONTRIBUTING.md](CONTRIBUTING.md)를 참조하세요._
