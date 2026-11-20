> **Languages:** [English](../QUICKSTART.md) · [العربية](../ar/QUICKSTART.md) · [Čeština](../cs/QUICKSTART.md) · [Deutsch](../de/QUICKSTART.md) · [Español](../es/QUICKSTART.md) · [فارسی](../fa/QUICKSTART.md) · [Français](../fr/QUICKSTART.md) · [हिन्दी](../hi/QUICKSTART.md) · [Bahasa Indonesia](../id/QUICKSTART.md) · [Italiano](../it/QUICKSTART.md) · 日本語 · [한국어](../ko/QUICKSTART.md) · [Nederlands](../nl/QUICKSTART.md) · [Polski](../pl/QUICKSTART.md) · [Português](../pt/QUICKSTART.md) · [Русский](../ru/QUICKSTART.md) · [Svenska](../sv/QUICKSTART.md) · [ไทย](../th/QUICKSTART.md) · [Türkçe](../tr/QUICKSTART.md) · [Українська](../uk/QUICKSTART.md) · [Tiếng Việt](../vi/QUICKSTART.md) · [中文](../zh/QUICKSTART.md)

---

# VDLU 導入クイックスタート

**VDLiveUpdate** をモジュールに vendor するためのコピー&ペースト式チェックリスト。VDLU 自体はモジュールでは
ない: `<module>/vdlu/` に配置され、あなたのモジュールの zip の中に同梱される。完全な論拠については
[`INTERFACES.md`](INTERFACES.md) (seam 契約)、[`ENGINE.md`](ENGINE.md)、[`PRODUCER.md`](PRODUCER.md)、
[`WEBUI.md`](WEBUI.md) を参照。

`<id>` をあなたの署名鍵の id に、`<abi>` をあなたが出荷するデバイスの ABI (`arm64-v8a`、`armeabi-v7a`、
`x86_64`、`x86`) に、`<module>` をあなたのモジュールツリーに置き換える。

## ターゲットレイアウト

これは導入後にモジュールが保持する正確な `vdlu/` ツリーである:

```
<module>/
├── module.prop
├── post-fs-data.sh            # pre-zygote トリガー: sh "$MODDIR/vdlu/update.sh" boot
├── webroot/
│   └── index.html             # あなたの WebUI、Updates パネルを配線 (手順 5)
└── vdlu/
    ├── update.sh              # エンジン (バイト単位で vendor)
    ├── vdlu-verify            # ed25519 検証シム (デバイス側、openssl なし)
    ├── verify/
    │   └── <abi>/ed25519-mini # ABI ごとの検証バイナリ
    ├── keyring/
    │   └── <id>.pub           # RAW 32 バイト公開鍵 (決して PEM ではない)
    ├── config.default         # profile + source + 自動化のデフォルト
    └── baseline.json          # インストール seed (署名なし、鍵なし)
```

エンジンの可変状態 (`config`、`current.json`、journal、ロック) は、モジュールディレクトリの外の Tier-2、
`/data/adb/<modid>/vdlu/` に存在する。`config.default` が初回実行時にそれを seed する。

## 1. エンジンを vendor する

エンジン、検証シム、ABI ごとの検証ツールを `<module>/vdlu/` にコピーする:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh      <module>/vdlu/update.sh
cp engine/vdlu-verify    <module>/vdlu/vdlu-verify
cp -r verify/<abi>       <module>/vdlu/verify/<abi>      # ABI ごとの ed25519-mini
```

サポートする ABI だけを出荷する。`customize.sh` はインストール時に `verify/` をデバイスの ABI に刈り込む
ことができる。

## 2. 署名鍵を生成する (一度きり)

```sh
producer/vdlu-keygen <id> ./keys
```

これは `<id>.pem` (秘密。あらゆるデバイスおよびあらゆるリポジトリへの push から外しておくこと)、`<id>.pub`
(PEM、PC 側のみ)、`<id>.pub.raw` (RAW 32 バイト、デバイスの keyring 用) を出力する。

## 3. 生の公開鍵を埋め込む

デバイスの keyring は **RAW 32 バイト**の鍵を保持し、決して PEM ではない (`ed25519-mini` は PEM を読めない):

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

keyring はリリースをまたいで安定している (鍵のローテーション時にのみ変わる): 再 vendor の際は、**上書きせず
検証する**こと。

## 4. config を書く

`config.default` を `<module>/vdlu/` に出荷する (初回実行時に Tier-2 の `config` を seed する):

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # 公開フィード: 署名必須、ダウングレードブロック
net_policy=any
pubkey_dir=keyring
```

`profile=trusted` は私的な `file://`/SSH ソースにのみ使用する (検証はベストエフォート。すべての blob の
sha256 は依然としてチェックされる)。リテラルの `trusted` 以外の値は `hardened` として扱われる (fail-closed)。

## 5. トリガーを配線する

**reboot 時** (`auto_on_reboot`): エンジンを `post-fs-data.sh` から pre-zygote で呼び出し、ステージされた
ファイル (`.so`、`/system` オーバーレイ、`sepolicy.rule`) が追加の reboot なしに swap されるようにする:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**WebUI オープン時** (`auto_on_webui_open`): ドロップイン式の Updates パネルをあなたの `webroot/index.html`
に配線する:

```html
<link rel="stylesheet" href="vdlu.css">
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,
    vdluDir:   '/data/adb/' + MODID + '/vdlu',
    modid:     MODID,
    module:    'YourModule'
  });
  VDLU.onWebUIOpen();                                             // evaluates journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // the "Updates" tab
</script>
```

(`vdlu.js` / `vdlu.css` は `webui/` から vendor される。翻訳は `i18n: window.VDLU_I18N_<LANG>` で追加
できる。)

## 6. リリースワークフローでフィードに署名する

各リリースで、最終的なモジュールツリーをパックし、manifest に署名する。秘密鍵は運用者のマシンに保持し、決して
CI には置かない:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]        # delete[] = prev 以降に消えたパス
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# ./out/{manifest.json,blobs/} を <source> に公開する
```

## 7. ベースラインを出荷する

出荷するツリーに対して `baseline.json` を生成し、`<module>/vdlu/baseline.json` に配置する。これは新規
インストール時に `current.json` を seed し、デバイスが「current」な状態で生まれるようにする (再取得なし)。
これは**ローカルの信頼された seed** である: 署名なし・鍵なしなので、CI は署名鍵に一切触れずにそれをビルド
できる:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

不在でも致命的ではない (デバイスは最初の更新で単に `0` から始まるだけである)。

---

導入は以上である。`sh -n <module>/vdlu/update.sh` が通らなければならない。出荷の前に、
[`PRODUCER.md`](PRODUCER.md) とルートの README に示されるように、プロデューサとエンジンをエンドツーエンドで
テストすること。

<!-- doc-footer -->

---

> _このドキュメントは Claude (Anthropic) で生成され、VD171 によって保守されています。修正や改善を歓迎します。[CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。_
