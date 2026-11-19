<!--
  ======================================================================
   VDLiveUpdate (VDLU)  ::  flashless, incremental module updates
   A self-update engine for KernelSU/APatch/Magisk modules: fetch only the
   files that changed, apply the live ones with no reboot, verified by ed25519.

   Copyright (C) 2026  VD171
   SPDX-License-Identifier: Apache-2.0

   Licensed under the Apache License, Version 2.0; you may obtain a copy at
   http://www.apache.org/licenses/LICENSE-2.0

   Site           : https://vd171.ru
   Site           : https://vd.priv8.ru
   Source         : https://github.com/VD171/VDLiveUpdate
   GitHub         : @VD171 https://github.com/VD171
   XDA-Developers : @VD171 https://xdaforums.com/m/vd171.4699873/
   Telegram       : @VD_Priv8 https://t.me/VD_Priv8
   Channel        : @Priv8_VD https://t.me/Priv8_VD
   Discord        : @VD.Priv8 https://discord.com/users/1296831918989639721
   E-mail         : vd.priv8@pm.me
  ======================================================================
-->

# VDLiveUpdate

> **Languages:** [English](README.md) · [العربية](README.ar.md) · [Čeština](README.cs.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [فارسی](README.fa.md) · [Français](README.fr.md) · [हिन्दी](README.hi.md) · [Bahasa Indonesia](README.id.md) · [Italiano](README.it.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Svenska](README.sv.md) · [ไทย](README.th.md) · [Türkçe](README.tr.md) · [Українська](README.uk.md) · [Tiếng Việt](README.vi.md) · [中文](README.zh.md)

**VDLU** 는 **KernelSU / APatch / Magisk** 모듈을 위한, 플래시가 필요 없는 증분 자체 업데이트 엔진입니다. 설치된 모듈은 **변경된 파일만** (콘텐츠 주소 지정 블롭 + 서명된 매니페스트) 가져와 자신을 업데이트하고, 라이브한 파일은 **재부팅 없이** 적용하며, 재부팅이 필요한 소수의 파일 (`.so`, `/system` 오버레이, `sepolicy.rule`) 만 스테이징하고 표시합니다. root 매니저도, 전체 `.zip` 재다운로드도, 스테이징된 파일을 위한 경우를 제외한 재부팅도 없습니다.

VDLU 는 모듈 자체로 실행되는 것이 아니라, 모듈 안에 **벤더링** (vendor, `<module>/vdlu/` 에 배치) 되도록 설계되었습니다.

## 이유

일반적인 모듈 업데이트는 `.zip` 전체를 다시 배포합니다. 큰 모듈의 경우, 몇 줄의 변경을 위해 큰 재다운로드가 발생하며, 정적 업데이트 매니페스트는 하나의 `zipUrl` 만 가리킬 수 있어 기기가 실제로 가진 플레이버 (ABI, full 대 lite) 를 제공할 수 없습니다. VDLU 는 **설치된** 트리를 서명된 피드와 비교하여 델타만 가져오므로, arm64-full 설치는 arm64-full 로, lite 설치는 lite 로 유지되며 대부분의 업데이트는 라이브로 적용됩니다.

## 동작 방식

- **프로듀서 (PC / 릴리스):** `vdlu-pack` 은 모듈 트리를 콘텐츠 주소 지정 피드 (`manifest.json` + `blobs/<sha256>`, gzip, 중복 제거, `delete[]`) 로 변환합니다. `vdlu-keygen` / `vdlu-sign` (ed25519). `vdlu-gc` 는 최근 N 개 매니페스트에 대한 참조를 기준으로 고아 블롭을 정리합니다 (페일세이프, 기본값은 dry-run).
- **엔진 (기기):** POSIX sh, `jq` 불필요. `update.sh` (`check | run | resume | boot | status | cancel`) 는 DIFF -> FETCH -> APPLY -> COMMIT 를 **재개 가능한 트랜잭션** (저널) 으로 실행하며, 롤백과 `mkdir` 잠금을 갖춥니다. 서명은 내장된 `ed25519-mini` 로 검증됩니다 (기기에 `openssl` 불필요).
- **WebUI:** 드롭인 Updates 패널 (진행 상황 토스트, 취소, 재부팅 배너), 바닐라 JS.

## 프로파일

- `trusted`: 비공개 용도, `file://` 또는 SSH 소스, 베스트 에포트 검증 (해시는 항상).
- `hardened`: 공개 용도, **서명 필수**, 다운그레이드 차단. 매니페스트는 **모듈 id 에 바인딩** 되며, 무엇이든 다운로드하기 전에 모든 필드가 페일클로즈드로 검증됩니다.

## 자신의 모듈에 도입하기

`engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` 를 `<module>/vdlu/` 에 벤더링하고, **원시 32바이트 공개 키** 를 `vdlu/keyring/<id>.pub` 로 탑재하며, `config` (프로파일 + 소스) 를 추가하고, 트리거를 연결하고 (부팅 시 자동 업데이트를 위한 `post-fs-data.sh` pre-zygote, WebUI 열림 트리거), 릴리스에 `vdlu-pack` + `vdlu-sign` 을 추가합니다. 실제 적용 템플릿은 [`integration/`](integration/) 을 참조하세요.

## 보안

- **매니페스트의 모든 필드는 적대적 입력입니다.** `validate_plan()` 은 절대 경로나 `..` 경로, 64자리 16진수가 아닌 `sha256`, 잘못된 mode / class / encoding 이 있으면 **어떤 가져오기나 적용보다 먼저** 매니페스트 전체를 페일클로즈드로 거부합니다.
- **서명용 개인 키는 CI 나 기기에 결코 닿지 않습니다.** 원시 공개 키만 임베드되며, 검증에는 `openssl` 이 아니라 `ed25519-mini` 를 사용합니다.
- `hardened` 는 역전을 통해 페일클로즈드입니다. 문자 그대로의 `trusted` 이외의 모든 값은 `hardened` 로 취급되므로, 프로파일 값이 손상되어도 서명되지 않은 매니페스트가 조용히 수락되는 일은 결코 없습니다.
- 재부팅이 필요한 파일 (`.so`, `/system` 오버레이, `sepolicy.rule`) 은 **스테이징되며 라이브 inode 위에 덮어써지지 않습니다**. 그 외의 모든 것은 라이브로 적용됩니다. 적용에 실패하면 백업 없이 덮어쓰는 대신 중단합니다.

## 빌드 / 테스트

스크립트이며 컴파일할 것이 없습니다. 엔드투엔드 (프로듀서 + 엔진 함께):

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

`sh -n engine/*.sh`, `node --check webui/vdlu.js`, 그리고 `webui/demo.html` 을 브라우저에서 엽니다 (기기 브리지를 모킹합니다).

## 문서

- [`INTERFACES.md`](docs/INTERFACES.md): 컴포넌트 간 접합부 계약 (수렴의 법칙. 불변의 것으로 취급하세요).
- `integration/`: 단계별 도입 가이드와 연결 스니펫.

## 함께 보기

같은 작성자의 자매 프로젝트:

- **[VDBackup](https://github.com/VD171/VD-Backup)**: 앱과 데이터의 완전한 백업 및 복원을 root 로 수행하며, 전적으로 WebUI 에서 조작합니다.
- **[COPG-VD](https://github.com/VD171/COPG-VD)**: 새로운 핑거프린트를 일관되고 정합성 있는 프로파일로 바꾸는 기기 스푸퍼.
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: KernelSU/APatch/Magisk 를 위한 단독 실행형 설정 가능 root SSH 데몬.
- **[VDInfos](https://github.com/VD171/VD-Infos)**: 각 항목을, 그것을 읽을 수 있는 모든 메서드로 읽어내는 기기 메서드 디버거.
- **[VDGoogle](https://github.com/VD171/VD-Google)**: Google 이 당신의 기기에 기록하는 내용을, 완전히 기기 상에서 인터넷 없이 읽어냅니다.

## 연락처

- https://vd171.ru
- https://vd.priv8.ru
- **Telegram:** @VD_Priv8 https://t.me/VD_Priv8
- **Channel:** @Priv8_VD https://t.me/Priv8_VD
- **Discord:** @VD.Priv8 https://discord.com/users/1296831918989639721
- **E-mail:** vd.priv8@pm.me
- **XDA-Developers:** @VD171 https://xdaforums.com/m/vd171.4699873/
- **GitHub:** @VD171 https://github.com/VD171

## 라이선스

VDLiveUpdate 자체 코드는 **Apache-2.0** 입니다. [LICENSE](LICENSE) 를 참조하세요. 작은 `ed25519-mini`
검증기와 가져오기 부트스트랩용 정적 `curl` 을 벤더링하며, 각각 고유의 라이선스 아래에 있습니다.
[NOTICE.md](NOTICE.md) 와 동봉된 바이너리 옆의 `PROVENANCE.json` 파일을 참조하세요.

## 상표

VDLiveUpdate 는 독립적인 비공식 프로젝트이며, 어떤 제3자와도 제휴하거나 승인받지 않았습니다.
"Android" 는 Google LLC 의 상표입니다. "KernelSU", "Magisk", "APatch" 는 각 작성자의 상표입니다.
VDLU 는 전적으로 당신의 기기와 당신 자신의 릴리스 호스트에서 동작합니다.

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`

---

📣 **Join the channel for updates:** @Priv8_VD https://t.me/Priv8_VD
