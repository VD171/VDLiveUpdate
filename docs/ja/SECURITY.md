> **Languages:** [English](../../SECURITY.md) · [العربية](../ar/SECURITY.md) · [Čeština](../cs/SECURITY.md) · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · [فارسی](../fa/SECURITY.md) · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · [Italiano](../it/SECURITY.md) · 日本語 · [한국어](../ko/SECURITY.md) · [Nederlands](../nl/SECURITY.md) · [Polski](../pl/SECURITY.md) · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · [中文](../zh/SECURITY.md)

---

# セキュリティポリシー

VDLiveUpdate (VDLU) は、稼働中のモジュールに flashless な root アップデートを適用します。
モジュール自身のディレクトリに書き込み、起動時に Zygisk の `.so` を入れ替え、モジュールの
root コンテキストで動作します。私たちはセキュリティを重視しています。

## 脆弱性の報告

- **Site:** https://vd171.ru
- **Site:** https://vd.priv8.ru
- **Issues:** https://github.com/VD171/VDLiveUpdate/issues
- **GitHub:** [@VD171](https://github.com/VD171)
- **XDA-Developers:** [@VD171](https://xdaforums.com/m/vd171.4699873/)
- **Telegram:** [@VD_Priv8](https://t.me/VD_Priv8)
- **Channel:** [@Priv8_VD](https://t.me/Priv8_VD)
- **Discord:** [@VD.Priv8](https://discord.com/users/1296831918989639721)
- **E-mail:** vd.priv8@pm.me

明確な説明と、可能であれば問題を再現する manifest または feed を含めてください。できるだけ
早く対応し、ご希望であればクレジットを記載します。

## スコープに関する注意

- アップデートは content-addressed なブロブと、ed25519 で署名された `manifest.json` です。
  デバイスは組み込みの `ed25519-mini` で署名を検証し (デバイス上に openssl はありません)、
  各ブロブは使用前に自身の `sha256` と照合されます。
- hardened プロファイル (公開のデフォルト) は有効な署名を必須とし、downgrade をブロックし
  ます。「元の」バージョンはインストール済みモジュールの `versionCode` (`module.prop` から
  読み取り) によって下限が定められるため、モジュールが feed より後ろへ戻されることはありま
  せん。
- 信頼の起点 (`keyring/` 内の生の ed25519 公開鍵と `verify/` のバイナリ) は flash 専用で、
  ネットワーク越しにローテーションされることはありません。プロデューサーはそれを feed から
  除外し、engine は取得したプランの中のすべての `vdlu/` パスを無視するため、漏洩した署名鍵
  が検証器や鍵を入れ替えて root を永続化することはできません。
- 別のモジュール向けに正当に署名された manifest が、異なるモジュールのディレクトリに書き込
  むことはできません。署名された `module` フィールドはデバイス上の `MODID` と一致している必
  要があり (モジュール間バインドチェック)、すべての書き込みと削除はモジュールディレクトリ内
  に限定されます。
- engine はモジュール自身の root コンテキストで動作し、それを弱めることは決してありません。
  権限を追加せず、manifest のどのフィールドも shell に展開しません。`path`、`sha256`、
  `mode`、`delete[]` の各値は、使用前に敵対的な入力として検証されます。
- 姿勢は fail-closed です。破損した、または不明な `profile` 値が、署名なしコンテンツの受け
  入れへすり抜けることは決してありません (`trusted` と厳密に一致しないものはすべて `hardened`
  として扱われます)。また、いずれのファイルも上書きされる前にバックアップが書き込まれるため、
  失敗した apply がインストール済みバージョンを破壊することはありません。
- 完全な信頼モデル、fail-closed の保証、hardening の詳細については
  [TRUST-MODEL.md](TRUST-MODEL.md) を参照してください。

<!-- doc-footer -->

---

> _このドキュメントは Claude (Anthropic) で生成され、VD171 によって保守されています。修正や改善を歓迎します。[CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。_
