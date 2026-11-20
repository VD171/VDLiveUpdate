# Contributing

貢献を歓迎します。VDLU は KernelSU / APatch / Magisk モジュールにベンダリングされる、
フラッシュ不要かつ増分的な自己更新エンジンです。このページは実践的な開発ワークフローです。
各部分がどう組み合わさるかは、まず [[Architecture]]、[[Engine]]、[[Producer]] を読んでください。

## 何もコンパイルしない

VDLU はスクリプト(POSIX sh、リリース側では少しの Python、WebUI にはバニラ JS)なので、
ビルドステップはありません。変更は、パイプラインを端から端まで実行し、各部分を静的チェックする
ことで検証します。

## まず継ぎ目の契約

コンポーネント間のインターフェース契約(エンジン、producer、WebUI が共有する CLI シグネチャ、
ファイル名、JSON キー)は**収束の法則**です。不変のものとして扱ってください。あなたの変更が
producer とエンジンの継ぎ目(マニフェストスキーマ、ジャーナルスキーマ、config キー、
署名/正準化ルール)に触れる場合、**まずインターフェース契約を揃え**、それから両側のコードを
それに合わせて変更してください。もう片方なしに継ぎ目の片側だけを変更すると、採用者を気づかないうちに
壊します。署名器と検証器がバイト単位で一致しなければならない正準化ルールについては [[Producer]] を
参照してください。

## PR の前に端から端までテストする

採用者のリリースと同じやり方で、使い捨てのツリー上で producer とエンジンを一緒に実行します:

```sh
# 1. a signing key
producer/vdlu-keygen demo /tmp/k

# 2. pack a module tree into a feed
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1

# 3. sign the manifest in place
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo

# 4. verify the manifest the way the device will (RAW 32B keyring)
engine/vdlu-verify /tmp/feed/manifest.json /tmp/keyring

# 5. drive the engine against the feed (source=file:///tmp/feed in the config)
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

それから各コンポーネントを静的チェックします:

```sh
sh -n engine/*.sh            # POSIX sh syntax, must pass
node --check webui/vdlu.js   # WebUI JS syntax
```

そして `webui/demo.html` をブラウザで開きます。root マネージャーのブリッジ(`ksu.exec`)を
モックするので、端末なしで Updates パネル、進捗トースト、キャンセル、再起動バナーを動かせます。
[[WebUI]] を参照してください。

## ハウスルール

- **端末上では POSIX sh。** `local` を超える bash 固有の構文はなく、`jq` もなし。toybox / busybox で
  動かなければなりません。
- **セキュリティは譲れない。** すべてのマニフェストフィールドは敵対的な入力です。`validate_plan()` は
  フェイルクローズドのまま保ち、秘密署名鍵は CI や端末に決して触れません。テストを通すために
  チェックを緩めないでください。
- **失敗時の厳格さ。** トランザクションを再開可能に保ってください。一致する再ハッシュなしに「done」と
  報告するものはなく、バックアップなしに上書きされるものはなく、適用はアトミックなままです。
- **常にリリース品質。** コメントは簡潔に保ち、無駄なコメントはなし。
- **PR ごとに一つの論理的変更。** 何が変わり、なぜかを述べてください。

## 課題を報告する

何をして、何を期待し、何が起きたかを説明する課題を開いてください。バグについては、モジュール id、
ソースプロファイル(`hardened` または `trusted`)、実行した `update.sh` コマンド、そして関連する
`journal.json`(フェーズ、状態、エラーを記録します)を含めてください。機能については、それがどの
コンポーネント(エンジン、producer、または WebUI)に触れるかを述べて、継ぎ目への影響を最初から
明確にしてください。
