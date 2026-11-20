# Producer

**producer**는 VDLU의 PC / 릴리스 측입니다: 완성된 모듈 트리를 기기가 업데이트할 수 있는 서명된 콘텐츠 주소화 피드로 바꾸는 작은 도구 모음입니다. 여기 있는 어떤 것도 폰에서 실행되지 않습니다. 이 도구들은 여러분의 릴리스 머신에서(또는 안전한 부분은 CI에서) 실행됩니다.

네 가지가 있습니다:

| 도구 | 실행 위치 | 언어 | 역할 |
|---|---|---|---|
| `vdlu-pack` | PC / CI | python3 | 최종 모듈 트리를 `manifest.json` + `blobs/<sha256>`로 순회 |
| `vdlu-keygen` | PC | sh + openssl | ed25519 서명 키쌍 생성 |
| `vdlu-sign` | PC | sh + openssl | 매니페스트에 `key_id` + 서명을 제자리에 주입 |
| `vdlu-gc` | PC | python3 | 게시된 피드에서 고아 블롭 정리(fail-safe) |

릴리스 흐름은 릴리스마다 한 번씩 하는 세 단계입니다: **pack, 그다음 sign, 그다음 publish**. `vdlu-keygen`은 일회성 설정이고, `vdlu-gc`는 피드가 커질 때 실행하는 정리 작업입니다. producer가 내보내는 모든 것은 [[Feed Format]]을 준수하며, 그것이 기기의 엔진이 소비하는 것입니다.

---

## vdlu-pack

`vdlu-pack`은 **여러분의 `.zip`이 배포하는 정확한 트리**(빌드가 자체 화이트리스트와 ABI 정리를 적용한 뒤의 최종 트리)를 받아 그에 대한 피드를 만듭니다.

```sh
vdlu-pack <module_tree_dir> <out_dir> <module_id> <version> \
          [--version-name v106] [--channel stable] [--prev ./prev/manifest.json]
```

`<out_dir>`에 두 가지를 씁니다:

- `manifest.json` - 대상 트리의 완전한 설명(각 파일의 `sha256`, `size`, `mode`, 인코딩, reboot 클래스), 여전히 **서명되지 않음**(`key_id`와 `sig` 필드는 빈 자리표시자).
- `blobs/<sha256>`(또는 `blobs/<sha256>.gz`) - 서로 다른 각 파일 콘텐츠마다 블롭 하나.

### 콘텐츠 주소화와 중복 제거

모든 블롭은 **그 원본(압축되지 않은) 콘텐츠의 sha256**으로 이름 붙여집니다. 이름이 해시이므로 동일한 콘텐츠는 같은 블롭에 안착합니다. `vdlu-pack`은 블롭이 아직 존재하지 않을 때만 쓰므로:

- 바뀌지 않은 파일은 같은 블롭 이름을 유지하고, 절대 다시 쓰이거나 다시 푸시되지 않습니다.
- 동일한 콘텐츠를 가진 서로 다른 두 파일은 하나의 블롭을 공유합니다.
- 되돌려진 파일은 이전부터 이미 있던 블롭을 재사용합니다.

따라서 게시는 **구성상 증분적**입니다: 릴리스 전반에 걸쳐 `blobs/`는 오직 커지기만 하고, 진정으로 새로운 콘텐츠만 추가됩니다. 기기는 같은 해시로 가져오므로, 아직 갖고 있지 않은 블롭만 다운로드합니다.

### 압축(`enc` 필드)

각 파일에 대해 `vdlu-pack`은 블롭을 어떻게 저장할지 결정합니다:

- 파일이 최소 4096바이트이고 **그리고** gzip(결정적 `-9 -n`)이 최소 10퍼센트를 절약할 때 `gz`.
- 그 외에는 `raw`(전송 중 gzip이 이미 커버하는 작은 파일, 또는 이미 압축 불가능한 데이터).
- 빌드 호스트에 `gzip`이 없으면 모든 것이 `raw`로 저장됩니다. packing은 이 때문에 절대 실패하지 않습니다.

매니페스트의 `sha256`은 **항상** 원본 콘텐츠의 것입니다. `enc`는 그 블롭이 어떻게 저장되었는지만 이름 붙입니다. 기기는 toybox `gunzip`으로 `gz` 블롭을 압축 해제한 다음 해시를 원본과 대조합니다.

### reboot 클래스와 안전

`vdlu-pack`은 또한 각 파일을 그 경로에서 도출한 reboot `class`(`live`, `soft`, `reboot`)로 태그하므로, 엔진은 재부팅 없이 적용할 수 있는 것과 스테이징해야 하는 것을 압니다. 규칙과 기기가 각 클래스로 하는 일은 [[Reboot Handling]]에서 다룹니다.

`vdlu-pack`이 의도적으로 하지 **않는** 몇 가지:

- 심볼릭 링크를 따라가지 않습니다(경고와 함께 건너뛰므로, 시스템 파일로의 링크 같은 트리 외부의 콘텐츠가 블롭으로 새어 들어갈 수 없습니다).
- 비정규 파일(디렉터리, fifo, 디바이스)을 건너뜁니다.
- `built` 타임스탬프에 `SOURCE_DATE_EPOCH`를 존중하므로 매니페스트가 재현 가능합니다.
- 고정된 경로 집합을 피드에서 전적으로 제외합니다(신뢰 루트, 설치 스캐폴딩, 그 밖의 몇 가지). 전체 목록과 각각이 왜 제외되는지는 [[Feed Format]]에 있습니다.

### `delete[]` 목록

`--prev <previous manifest.json>`을 전달하면 `vdlu-pack`이 `delete[]`를 계산합니다: 이전 릴리스에 있었지만 이번 릴리스에서 사라진 경로로, 기기가 고아를 뒤에 남기는 대신 제거하도록 합니다. 제외된 경로는 이전 매니페스트에 나타나더라도 절대 삭제로 내보내지지 않습니다(정확한 의미론은 [[Feed Format]] 참조).

---

## vdlu-keygen

일회성 단계입니다. `vdlu-keygen`은 여러분의 피드를 위한 ed25519 서명 키쌍을 만듭니다.

```sh
vdlu-keygen <id> <out_dir>
```

세 파일을 씁니다:

| 파일 | 무엇인지 | 어디로 가는지 |
|---|---|---|
| `<id>.pem` | **개인** 서명 키(모드 `0600`) | 여러분의 릴리스 머신에 머묾. 절대로. |
| `<id>.pub` | PEM 형식의 공개 키 | PC 측 도구 전용 |
| `<id>.pub.raw` | **원시 32바이트** 형식의 공개 키 | 모듈의 기기 내 keyring 항목으로 배포됨 |

원시 32바이트 공개 키가 기기 검증기가 읽는 것입니다(`openssl`을 싣지 않으므로 PEM을 읽을 수 없습니다). `<id>.pub.raw`를 모듈에 `vdlu/keyring/<id>.pub`로 내장합니다. PEM은 PC 측 사용 전용입니다. 이 분리와 키 회전이 어떻게 작동하는지는 [[Security and Trust Model]]에 설명되어 있습니다.

> 개인 `.pem`은 전체 시스템에서 유일한 비밀입니다. 모든 기기에서 떨어뜨려 두고 모든 저장소 푸시에서 빼 두세요. 아래 CI 노트를 참조하세요.

---

## vdlu-sign

`vdlu-sign`은 `vdlu-pack`이 생성한 서명되지 않은 매니페스트를 받아 **제자리에서** 서명합니다.

```sh
vdlu-sign <manifest.json> <privkey.pem> <key_id>
```

`key_id` 필드를 설정하고, 매니페스트의 정규 형식을 계산하고, ed25519 서명(base64)을 `sig` 필드에 씁니다. 서명은 매니페스트의 정밀한 바이트 변환에 대한 것이라서, PC와 기기가 기기에 JSON 라이브러리 없이도 정확히 같은 서명 바이트를 도출합니다. 그 변환(**정규화**)은 이 포맷에서 가장 중요한 단일 불변식이며, [[Feed Format]]에 전부 문서화되어 있습니다.

개인 키는 여기, 여러분의 머신에서만 읽히고, 절대 떠나지 않습니다.

### 서명 키는 CI에서 벗어나 있음

이것은 의도적인 설계 지점입니다. CI는 `vdlu-pack`을 실행하여 완벽히 유효한 **키 없는 베이스라인**(서명되지 않은 seed 매니페스트, [[Feed Format]] 참조)을 만들 수 있으므로, CI가 개인 키에 한 번도 닿지 않고도 새 설치가 current 상태로 태어납니다. 게시되는 피드의 실제 서명은 여러분이 로컬에서 `vdlu-sign`으로 합니다. 그렇게 해서 서명 키는 CI에서 100퍼센트 벗어나 있고, 여러분이 손으로 게시하는 피드만 서명됩니다.

---

## vdlu-gc

블롭은 콘텐츠 주소화되어 있고 불변이므로, `blobs/`는 오직 커지기만 합니다: `vdlu-pack`은 추가하고, 절대 제거하지 않습니다. 많은 릴리스를 거치면 피드(그리고 그것을 호스팅하는 Pages 사이트)는 더 이상 어떤 현재 매니페스트도 참조하지 않는 블롭을 쌓아 갑니다. `vdlu-gc`가 그 고아들을 정리합니다.

```sh
vdlu-gc <feed_dir> [--keep-last N] [--keep extra.json ...] [--apply]
```

**보존 집합(retained set)**의 매니페스트를 만듭니다: 현재 `manifest.json`, 더하기 버전 기준 마지막 `N`개의 아카이브된 매니페스트(기본 `N=3`, 롤백 여유를 줌), 더하기 `--keep`으로 지정한 것. **어떤** 보존된 매니페스트에도 참조되지 않는 블롭은 고아이며 제거 후보입니다. 보존 집합은 합집합이므로, 보존된 릴리스 중 하나라도 여전히 필요로 하는 한 블롭은 남습니다. 더 오래된 보존 버전에 앉아 있는 기기는 자기 fetch를 절대 잃지 않습니다.

`vdlu-gc`는 안전하게 만들어졌습니다:

- **기본 Dry-run.** `--apply` 없이는 제거*할* 것만 출력합니다. 실제로 삭제하려면 `--apply`를 추가합니다.
- **Fail-safe.** 보존된 매니페스트를 하나도 찾지 못하면, 피드를 비울 위험을 무릅쓰는 대신 정리를 거부합니다.
- **날짜가 아닌 참조에 의한 보존.** 블롭은 보존된 매니페스트가 그것을 가리키기 때문에 유지되며, 타임스탬프 때문이 절대 아닙니다.

정리한 뒤, 더 작아진 피드를 호스트에 푸시합니다. 호스트가 배치 쓰기에 rate-limit을 건다면 쓰기를 분산하세요.

---

## 한데 모으기

전형적인 릴리스, 처음부터 끝까지:

```sh
# one-time: make a signing key. Keep the .pem off every device and every repo push.
vdlu-keygen release-2026 ./keys

# each release: pack the final shipped tree (post-whitelist, same tree the .zip ships)
vdlu-pack ./module_tree ./out demo 106 --version-name v106 --channel stable \
          --prev ./prev/manifest.json

# sign the manifest in place (local, private key never leaves your machine)
vdlu-sign ./out/manifest.json ./keys/release-2026.pem release-2026

# publish ./out/{manifest.json,blobs/} to your source (GitHub Pages, rsync, ...).
# occasionally: prune orphan blobs
vdlu-gc ./feed --keep-last 3            # dry-run first
vdlu-gc ./feed --keep-last 3 --apply    # then delete
```

VDLU를 모듈에 도입하는 전체 작업 예시는 [[Quick Start]]를 참조하세요. producer가 내보내는 모든 것의 전송 형태는 [[Feed Format]]을 참조하세요. 키 처리의 배경 논리와 피드에서 무엇을 빼 두는지는 [[Security and Trust Model]]을 참조하세요.
