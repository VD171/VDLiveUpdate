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

**VDLU** は、**KernelSU / APatch / Magisk** モジュール向けの、フラッシュ不要で増分的な自己更新エンジンです。インストール済みのモジュールは、**変更されたファイルだけ** (コンテンツアドレス指定のブロブ + 署名付きマニフェスト) を取得して自分自身を更新し、ライブなものを **再起動なしで** 適用し、再起動が必要な少数のファイル (`.so`、`/system` オーバーレイ、`sepolicy.rule`) だけをステージングしてフラグを立てます。root マネージャーも、`.zip` 全体の再ダウンロードも、ステージングされたファイルのための以外の再起動もありません。

VDLU は、モジュール自体として動かすのではなく、モジュールに **ベンダリング** (vendor、`<module>/vdlu/` に配置) されるように設計されています。

## なぜ

通常のモジュール更新は `.zip` 全体を再び配布します。大きなモジュールでは、数行の変更のために大量の再ダウンロードが発生し、静的な更新マニフェストは `zipUrl` を一つしか指せないため、デバイスが実際に持っているフレーバー (ABI、full か lite か) を配信できません。VDLU は **インストール済み** のツリーを署名付きフィードと差分し、デルタだけを取得します。そのため arm64-full のインストールは arm64-full のまま、lite のインストールは lite のままとなり、ほとんどの更新はライブで適用されます。

## 仕組み

- **プロデューサー (PC / リリース):** `vdlu-pack` はモジュールツリーをコンテンツアドレス指定のフィード (`manifest.json` + `blobs/<sha256>`、gzip、重複排除、`delete[]`) に変換します。`vdlu-keygen` / `vdlu-sign` (ed25519)。`vdlu-gc` は直近 N 個のマニフェストへの参照を基準に孤立したブロブを刈り込みます (フェイルセーフ、デフォルトは dry-run)。
- **エンジン (デバイス):** POSIX sh、`jq` 不要。`update.sh` (`check | run | resume | boot | status | cancel`) は DIFF -> FETCH -> APPLY -> COMMIT を **再開可能なトランザクション** (ジャーナル) として実行し、ロールバックと `mkdir` ロックを備えます。署名は組み込みの `ed25519-mini` で検証されます (デバイスに `openssl` は不要)。
- **WebUI:** ドロップインの Updates パネル (進捗トースト、キャンセル、再起動バナー)、バニラ JS。

## プロファイル

- `trusted`: プライベート用途、`file://` または SSH ソース、ベストエフォートの検証 (ハッシュは常に)。
- `hardened`: 公開用途、**署名は必須**、ダウングレードはブロックされます。マニフェストは **モジュール id に紐付けられ**、何かをダウンロードする前にすべてのフィールドがフェイルクローズドで検証されます。

## 自分のモジュールへ導入する

`engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` を `<module>/vdlu/` にベンダリングし、**生の 32 バイト公開鍵** を `vdlu/keyring/<id>.pub` として同梱し、`config` (プロファイル + ソース) を追加し、トリガーを配線し (起動時の自動更新のための `post-fs-data.sh` pre-zygote、WebUI オープン時のトリガー)、リリースに `vdlu-pack` + `vdlu-sign` を追加します。実践的なテンプレートは [`docs/QUICKSTART.md`](docs/QUICKSTART.md) を参照してください。

## セキュリティ

- **マニフェストのすべてのフィールドは敵対的な入力です。** `validate_plan()` は、絶対パスや `..` を含むパス、64 桁の 16 進数ではない `sha256`、不正な mode / class / encoding があれば、**フェッチや適用の前に** マニフェスト全体をフェイルクローズドで拒否します。
- **署名用の秘密鍵は CI にもデバイスにも一切触れません。** 埋め込まれるのは生の公開鍵だけで、検証には `openssl` ではなく `ed25519-mini` を使います。
- `hardened` は反転によってフェイルクローズドです。文字どおりの `trusted` 以外はすべて `hardened` として扱われるため、プロファイル値が破損しても、署名なしのマニフェストが黙って受け入れられることは決してありません。
- 再起動が必要なファイル (`.so`、`/system` オーバーレイ、`sepolicy.rule`) は **ステージングされ、ライブな inode の上に書き込まれることはありません**。それ以外はすべてライブで適用されます。適用に失敗した場合は、バックアップなしで上書きするのではなく中止します。

## ビルド / テスト

スクリプトであり、コンパイルするものはありません。エンドツーエンド (プロデューサー + エンジンを合わせて):

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

`sh -n engine/*.sh`、`node --check webui/vdlu.js`、そして `webui/demo.html` をブラウザで開きます (デバイスブリッジをモックします)。

## ドキュメント

- [`INTERFACES.md`](docs/INTERFACES.md): コンポーネント間の接合部の契約 (収束の法則。不変のものとして扱ってください)。
- [`ENGINE.md`](docs/ENGINE.md): デバイス側エンジン (`update.sh`): 再開可能な DIFF -> FETCH -> APPLY -> COMMIT トランザクション。
- [`PRODUCER.md`](docs/PRODUCER.md): PC/リリース側: コンテンツアドレス指定フィードのビルドと署名 (`vdlu-pack`、`vdlu-sign`)。
- [`WEBUI.md`](docs/WEBUI.md): 組み込み型の Updates パネルウィジェット (進捗トースト、キャンセル、再起動バナー)。
- [`docs/QUICKSTART.md`](docs/QUICKSTART.md): ステップバイステップの導入ガイドと配線スニペット。

## 関連項目

同じ作者による姉妹プロジェクト:

- **[VDBackup](https://github.com/VD171/VD-Backup)**: アプリとデータの完全なバックアップと復元を root で行い、すべて WebUI から操作します。
- **[COPG-VD](https://github.com/VD171/COPG-VD)**: 新しいフィンガープリントを、首尾一貫した整合性のあるプロファイルに変えるデバイススプーファー。
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: KernelSU/APatch/Magisk 向けの、単体で動く設定可能な root 権限 SSH デーモン。
- **[VDInfos](https://github.com/VD171/VD-Infos)**: 各項目を、それを読み取れるあらゆるメソッドで読み取るデバイスメソッドデバッガー。
- **[VDGoogle](https://github.com/VD171/VD-Google)**: Google があなたのデバイスに記録している内容を、完全にデバイス上で、インターネットなしで読み取ります。

## 連絡先

- https://vd171.ru
- https://vd.priv8.ru
- **Telegram:** @VD_Priv8 https://t.me/VD_Priv8
- **Channel:** @Priv8_VD https://t.me/Priv8_VD
- **Discord:** @VD.Priv8 https://discord.com/users/1296831918989639721
- **E-mail:** vd.priv8@pm.me
- **XDA-Developers:** @VD171 https://xdaforums.com/m/vd171.4699873/
- **GitHub:** @VD171 https://github.com/VD171

## ライセンス

VDLiveUpdate 自体のコードは **Apache-2.0** です。[LICENSE](LICENSE) を参照してください。小さな `ed25519-mini`
検証器と、フェッチのブートストラップ用の静的な `curl` をベンダリングしており、それぞれが独自のライセンスのもとにあります。
[NOTICE.md](NOTICE.md) と、同梱バイナリの隣にある `PROVENANCE.json` ファイルを参照してください。

## 商標

VDLiveUpdate は独立した非公式のプロジェクトであり、いかなる第三者とも提携、承認の関係にありません。
「Android」は Google LLC の商標です。「KernelSU」「Magisk」「APatch」はそれぞれの作者の商標です。
VDLU は完全にあなたのデバイス上と、あなた自身のリリースホスト上で動作します。

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`

---

📣 **Join the channel for updates:** @Priv8_VD https://t.me/Priv8_VD
