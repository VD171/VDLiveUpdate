# Quick Start

これは導入チェックリストです。**VDLiveUpdate (VDLU)** を KernelSU / APatch / Magisk
モジュールにベンダリングする方法です。VDLU はそれ自体がモジュールではありません。
`<module>/vdlu/` にドロップインされ、あなたのモジュールの zip の内側に同梱されるので、
インストール済みのモジュールが、あなたが公開する署名付きフィードから自身をフラッシュ不要で更新できます。

全体を通じて、`<id>` をあなたの署名鍵の id に、`<abi>` をあなたが配布する端末の
ABI(`arm64-v8a`、`armeabi-v7a`、`x86_64`、`x86`)に、`<module>` をあなたのモジュールツリーに
置き換えてください。

各部分の根拠については [[Engine]]、[[Producer]]、[[WebUI]]、[[Security and Trust Model]] を参照してください。

## モジュール内の `vdlu/` レイアウト

これは導入後にモジュールが運ぶ正確なツリーです:

```
<module>/
|-- module.prop
|-- post-fs-data.sh            # pre-zygote trigger: sh "$MODDIR/vdlu/update.sh" boot
|-- webroot/
|   `-- index.html             # your WebUI, wiring the Updates panel (step 5)
`-- vdlu/
    |-- update.sh              # the engine (vendored byte-for-byte)
    |-- vdlu-verify            # ed25519 verify shim (device-side, no openssl)
    |-- verify/
    |   `-- <abi>/ed25519-mini # per-ABI verifier binary
    |-- keyring/
    |   `-- <id>.pub           # RAW 32-byte public key (NEVER the PEM)
    |-- config.default         # profile + source + automation defaults
    `-- baseline.json          # install seed (unsigned, keyless)
```

エンジンの可変状態(`config`、`current.json`、ジャーナル、ロック、blob キャッシュ)は、
モジュールディレクトリの外、Tier-2 の `/data/adb/<modid>/vdlu/` に存在します。
`config.default` が初回実行時にその Tier-2 の `config` を種まきします。完全な状態レイアウトは
[[Engine]] を参照してください。

## 1. エンジンをベンダリングする

エンジン、verify シム、ABI ごとの検証器バイナリを `<module>/vdlu/` にコピーします:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh   <module>/vdlu/update.sh
cp engine/vdlu-verify <module>/vdlu/vdlu-verify
cp -r verify/<abi>    <module>/vdlu/verify/<abi>    # ed25519-mini per ABI
```

あなたがサポートする ABI だけを配布してください。`customize.sh` は、インストール時に `verify/` を
端末の ABI まで枝刈りできます。

## 2. 署名鍵を生成する(一度きり)

```sh
producer/vdlu-keygen <id> ./keys
```

これは三つのファイルを出力します:

- `<id>.pem` - 秘密鍵。すべての端末から遠ざけ、あらゆるリポジトリの push や CI シークレットから
  外しておいてください。
- `<id>.pub` - PEM 公開鍵。PC 側のみ(`vdlu-sign` が使用)。
- `<id>.pub.raw` - 生の 32 バイト公開鍵。端末キーリング用。

なぜ分離が重要かは [[Security and Trust Model]] を参照してください。

## 3. 生の公開鍵を埋め込む

端末キーリングは**生の 32 バイト**の鍵を保持し、PEM は決して保持しません。`ed25519-mini` は
PEM を読めないので、ここに PEM をコピーすると端末上の検証が壊れます:

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

キーリングはリリースをまたいで安定で、鍵のローテーション時にのみ変わります。再ベンダリング時は、
**それを検証してください、上書きしないでください**。

## 4. config を書く

`<module>/vdlu/` に `config.default` を配布します。これは初回実行時に Tier-2 の `config` を
種まきします:

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

`profile=trusted` はプライベートな `file://` または SSH ソースにのみ使ってください(そこでは
verify はベストエフォートですが、すべての blob の sha256 は依然としてチェックされます)。
リテラルの `trusted` 以外のあらゆる値は `hardened` として扱われ、フェイルクローズドです。
完全なプロファイルの意味論は [[Security and Trust Model]] を参照してください。

## 5. トリガーを組み込む

**On reboot**(`auto_on_reboot`): `post-fs-data.sh` からプリzygote でエンジンを呼び出すので、
ステージングされた再起動クラスのファイル(`.so`、`/system` オーバーレイ、`sepolicy.rule`)が
追加の再起動なしに入れ替わります:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**On WebUI open**(`auto_on_webui_open`): `webroot/index.html` でドロップイン型の Updates パネルを
組み込みます:

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
  VDLU.onWebUIOpen();                                            // journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // the "Updates" tab
</script>
```

`vdlu.js` と `vdlu.css` は `webui/` からベンダリングされます。翻訳は
`i18n: window.VDLU_I18N_<LANG>` で追加できます。パネルの契約は [[WebUI]] を参照してください。

## 6. リリースワークフローでフィードに署名する

リリースごとに、最終的なモジュールツリーをパックし、マニフェストに署名します。秘密鍵は
オペレーターのマシンに留め、CI には決して置かないでください:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> \
                    --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

`vdlu-pack` はコンテンツアドレス方式で重複排除するので、公開は増分的です。変更のない blob が
再プッシュされることは決してありません。[[Producer]] と [[Feed Format]] を参照してください。

## 7. ベースラインを配布する

配布するツリーに対して `baseline.json` を生成し、`<module>/vdlu/baseline.json` に配置します。
これは新規インストール時に `current.json` を種まきするので、端末は「current」として誕生し、
自身の配布バージョンを再取得しません。これは**ローカルの信頼されたシード**です。未署名で鍵なしなので、
CI は署名鍵に一切触れることなくそれをビルドできます:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

これはなくても致命的ではありません。端末は単に初回更新時にバージョン `0` から始めます。

---

これで導入のすべてです。配布する前に、`sh -n <module>/vdlu/update.sh` が通過しなければならず、
[[Contributing]] と [[Producer]] に示されているように producer とエンジンを端から端まで
テストすべきです。
