> **Languages:** [English](../PRODUCER.md) · [العربية](../ar/PRODUCER.md) · [Čeština](../cs/PRODUCER.md) · [Deutsch](../de/PRODUCER.md) · [Español](../es/PRODUCER.md) · [فارسی](../fa/PRODUCER.md) · [Français](../fr/PRODUCER.md) · [हिन्दी](../hi/PRODUCER.md) · [Bahasa Indonesia](../id/PRODUCER.md) · [Italiano](../it/PRODUCER.md) · [日本語](../ja/PRODUCER.md) · 한국어 · [Nederlands](../nl/PRODUCER.md) · [Polski](../pl/PRODUCER.md) · [Português](../pt/PRODUCER.md) · [Русский](../ru/PRODUCER.md) · [Svenska](../sv/PRODUCER.md) · [ไทย](../th/PRODUCER.md) · [Türkçe](../tr/PRODUCER.md) · [Українська](../uk/PRODUCER.md) · [Tiếng Việt](../vi/PRODUCER.md) · [中文](../zh/PRODUCER.md)

---

# VDLU 프로듀서 + 서명 레이어

모듈을 위한 콘텐츠 주소형 배포 (manifest + blobs)를 구축하고 서명한다.
[`INTERFACES.md`](INTERFACES.md) §3/§6/§7을 따른다.

| 도구 | 실행 위치 | 언어 | 역할 |
|---|---|---|---|
| `producer/vdlu-pack` | PC / CI | python3 | 최종 모듈 트리를 순회 -> `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | PC | sh + openssl | ed25519 키쌍 (`<id>.pem` 개인, `<id>.pub` PEM, 슬림 keyring용 `<id>.pub.raw` RAW 32B) |
| `producer/vdlu-sign` | PC | sh + openssl | manifest에 `key_id` + `sig`를 제자리에서 주입 |
| `engine/vdlu-verify` | **기기** | sh + ed25519-mini | 내장 ed25519-mini로 `sig`를 검증. keyring = RAW 32B 공개키 (기기에 openssl 없음) |

## 파이프라인

```sh
# 1. one-time: a signing key. Keep the .pem off every device and off any repo push.
producer/vdlu-keygen release-2026 ./keys

# 2. each release: pack the final tree (same tree the .zip ships, post-whitelist).
producer/vdlu-pack  ./module_tree  ./out  demo 106 --version-name v106 --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev

# 3. sign the manifest in place.
producer/vdlu-sign  ./out/manifest.json  ./keys/release-2026.pem  release-2026

# 4. publish ./out/{manifest.json,blobs/} to <source> (Pages batch for public; rsync for private).
#    The slim device keyring holds ./keys/release-2026.pub.raw as keyring/release-2026.pub (RAW 32B).
```

`vdlu-pack`은 콘텐츠 주소형이며 중복을 제거한다: `<sha256>`이 이미 존재하는 blob은 다시 쓰이지 않으므로,
퍼블리싱은 증분적이며 변경되지 않은 / 되돌려진 내용은 결코 다시 푸시되지 않는다.

### `enc` 결정 (vdlu-pack)

`sha256`은 **항상** 원본 (비압축) 내용에 대한 것이다. `enc`는 blob이 어떻게 저장되는지를 나타낼 뿐이다.

- `gz`: `size >= 4096` **그리고** gzip (`-9 -n`, 결정론적)이 최소 10%를 절약할 때 (`comp <= raw*0.90`).
- 그 외에는 `raw` (HTTP gzip이 이미 커버하는 작은 텍스트, 또는 이미 압축 불가능한 데이터).
- 빌드 호스트에 gzip 없음 -> 모두 `raw` (결코 실패하지 않음).

blob은 하나의 형식으로 한 번 저장된다: `blobs/<sha256>` (raw) 또는 `blobs/<sha256>.gz` (gz). 기기는
toybox `gunzip` (항상 존재함)으로 압축 해제하므로, zstd는 번들되지 않는다.

### `class` 결정 (vdlu-pack) - reboot 분류

경로에서 파생됨 (INTERFACES §3, doc §4). 기본값일 뿐. 경로 규칙은 결코 `reboot`->`live`로 다운그레이드하지 않는다.

| class | 매칭 대상 | 적용 방식 |
|---|---|---|
| `reboot` | `system/**`, `zygisk/**/*.so`, `*.rule` | `.vdlu-new`로 스테이징, boot에서 swap |
| `soft` | 루트의 `service.sh` / `post-fs-data.sh` / `boot-completed.sh` | 라이브에 기록, 다음 boot에 실행 |
| `live` | 그 외 모든 것 (webroot, bin, lib, confs, module.prop, ...) | 라이브에 기록, 원자적 |

심볼릭 링크는 **따라가지 않는다** (트리 밖의 내용, 예를 들어 `/etc/shadow`로의 링크를 결코 유출하지 않음) 며
경고와 함께 건너뛴다. manifest 스키마에 symlink 타입이 없기 때문이다. 정규 파일이 아닌 것 (디렉터리, fifo,
디바이스)은 건너뛴다. `built`는 재현 가능한 manifest를 위해 `SOURCE_DATE_EPOCH`를 존중한다.

### 베이스라인 (설치 seed) - 서명 없음, 키 없음

`baseline.json` (모듈 zip의 `vdlu/baseline.json`로 출시됨)은 새 설치 시 `current.json`을 seed하여
기기가 "current"로 태어나도록 한다 (from:0 없음, 재가져오기 없음). 엔진은 이를 **로컬의 신뢰된 seed**로
취급하며 (플래시된 zip에 담겨 도착했고, zip은 설치 신뢰 경계임) **그 서명을 검증하지 않는다** -
피드에서 FETCH된 manifest만이 `vdlu-verify`를 거친다. 따라서 베이스라인은 **키가 필요 없다**: 그것은
출시 트리에 대한 단순한 `vdlu-pack` 출력 (서명 없음. `sig`/`key_id`는 비어 있음)이다. 따라서 CI는
**키 없이** 그것을 생성할 수 있어, 서명 키를 CI에서 100% 배제할 수 있다 - 퍼블리시된 FEED만이 (운영자가, 로컬에서)
서명된다. `vdlu-pack`은 자신의 manifest에서 `baseline.json`을 제외한다 (자기 참조 방지). 부재해도 치명적이지 않음:
기기는 첫 업데이트에서 from:0으로 시작할 뿐, 결코 망가지지 않는다.

## 정규화 (수렴 지점)

`vdlu-sign`과 `engine/vdlu-verify`는 두 개의 서로 다른 런타임 (PC openssl 대 기기 toybox)에서,
manifest로부터 **같은 바이트**를 도출해야 한다. 이 규칙은 의도적으로 JSON 재직렬화가 아니라
바이트 변환이며, 기기에 JSON 라이브러리를 필요로 하지 않는다:

1. `vdlu-pack`은 `manifest.json`을 **컴팩트, 키 정렬, UTF-8**로 쓰고
   (`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`), 항상 필드
   `key_id`와 `sig`를 포함한다 (서명되기 전까지는 빈 문자열 플레이스홀더). 이것이 정규 저장 형식이다.
2. **정규형 = 그 텍스트에서 `"sig"` 필드를 제거한 것.** 키가 정렬되어 있으므로, `sig`
   는 항상 `,"sig":"<value>",`로 나타나며, `"schema"` (앞)와 `"version"` (뒤)으로 둘러싸인다.
   둘 다 항상 존재한다. 그것을 제거하면 잘 형성된 `...,"schema":N,"version":...`이 남는다.
   JSON은 문자열 값 내부의 모든 `"`를 `\"`로 이스케이프하므로, 구조 토큰 `"sig":"`는,
   문자 그대로 `"sig":"`를 포함하는 파일 이름에 대해서도 모호하지 않다 (테스트됨).
3. 서명/검증되는 메시지는 정규형의 **sha256 16진수** (64 ASCII 문자, 개행 없음)다. 그 16진수에 대한 ed25519
   (`openssl pkeyutl -sign/-verify -rawin`).

POSIX sh에서의 제거 (두 도구에서 동일한 함수, `sed`/`jq` 없음):

```sh
# $1 = full manifest text (trailing newline already stripped by $(cat ...))
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

`key_id`는 정규형의 일부다 (제거되는 것은 `sig`뿐). `vdlu-sign`은 해싱 **전에** `key_id`를 설정한다.
값 플레이스홀더가 비어 있든 (`"sig":""`, 서명 시) 채워져 있든 (검증 시) 동일한 정규 바이트를 산출하므로,
서명과 검증은 구성상 일치한다.

Python은 그것을 `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)` 후 sha256로 재현한다 - 
교차 검증용으로만 사용된다. 권위 있는 생성원은 두 개의 sh 도구다.

## 서명 (ed25519)

- `vdlu-keygen` (PC): `openssl genpkey -algorithm ed25519` (개인 `0600`) + `openssl pkey -pubout` (공개 **PEM**,
  서명/openssl용) + `openssl pkey -pubout -outform DER | tail -c 32` -> **`.pub.raw` (RAW 32B)** (ed25519
  SPKI DER은 12바이트 접두사 + 32바이트 키이므로, `tail -c 32`가 키 그 자체). 둘 다 방출한다.
- `vdlu-sign` (PC): 정규 sha256 16진수에 대한 `openssl pkeyutl -sign -rawin`. 서명은 base64로 저장된다.
- `vdlu-verify` (**기기, 슬림**): `ed25519-mini <pubkey32> <msg> <sig64>` - keyring을 **RAW 32B**
  공개키로 읽음. 기기에 openssl 없음. `key_id`는 경로가 정화된다 (`/`, `.`, `..`, `"` 없음). 🚨 keyring은
  **`.pub.raw` (32B)**를 출시하며, 결코 `.pub` PEM (113B)이 아니다: PEM은 PC 측 전용이고 `ed25519-mini`는 읽을 수 없다.

신뢰 모델 (INTERFACES §6, doc §11/§13): `profile=hardened` (공개)는 검증을 필수로 만든다 - 서명이
실패하거나 누락되면 업데이트를 중단한다. `profile=trusted` (사설, SSH로 스테이징된 소스)는 검증을
best-effort로 취급하지만, 모든 blob의 sha256은 무관하게 검사된다.

## keyring + 로테이션

keyring은 `<key_id>.pub` 파일들의 디렉터리이며, 각각 **RAW 32B** ed25519 공개키 (`keygen`의
`.pub.raw`에서 나옴)이고 PEM이 **아니다** - `ed25519-mini`는 raw 32바이트를 읽는다. 현재 키 **그리고** 이전의 raw 공개키를
출시할 것 (doc §13). 로테이션된 키가 오래된 설치를 벽돌로 만들지 않도록 하기 위함이다. `vdlu-sign`을 새 `key_id`로 하고
기기가 `<keyring>/<key_id>.pub` (raw)를 고르는 것, 이것이 로테이션 메커니즘의 전부다 - 엔진 변경 없음. keyring은
릴리스를 가로질러 **안정적**이다 (키 로테이션만이 그것을 변경함): 재벤더링은 **복사가 아니라 검증**해야 하며,
결코 PC 측 `.pub` PEM으로 덮어써서는 안 된다.

`vdlu-pack`은 **keyring과 `verify/` 바이너리를 피드에서 제외한다** (신뢰 루트는 플래시 전용이며, 결코 유선으로 제공되지 않는다). `baseline.json`, 인스톨러 스캐폴딩 (`META-INF/`, `customize.sh`), `.vd/` 플래시 게이트, CI가 채우는 `update.json`/`update-mmrl.json`, 그리고 파일별 `.sha256` 동반 파일도 마찬가지다. 피드로 업데이트할 수 있는 것은 모듈 자신의 내용뿐이므로, manifest가 기기의 신뢰 앵커를 다시 쓸 수는 결코 없다.

<!-- doc-footer -->

---

> _이 문서는 Claude (Anthropic)로 생성되었으며 VD171이 유지 관리합니다. 수정 및 개선을 환영합니다. [CONTRIBUTING.md](CONTRIBUTING.md)를 참조하세요._
