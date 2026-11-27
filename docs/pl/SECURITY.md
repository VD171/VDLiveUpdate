> **Languages:** [English](../../SECURITY.md) · [العربية](../ar/SECURITY.md) · [Čeština](../cs/SECURITY.md) · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · [فارسی](../fa/SECURITY.md) · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · [Italiano](../it/SECURITY.md) · [日本語](../ja/SECURITY.md) · [한국어](../ko/SECURITY.md) · [Nederlands](../nl/SECURITY.md) · Polski · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · [中文](../zh/SECURITY.md)

---

# Zasady bezpieczeństwa

VDLiveUpdate (VDLU) stosuje flashless aktualizacje z uprawnieniami root do działającego
modułu: zapisuje do własnego katalogu modułu i podmienia podczas startu bibliotekę `.so`
Zygisk, działając w kontekście root modułu. Traktujemy bezpieczeństwo poważnie.

## Zgłaszanie podatności

- **Site:** https://vd171.ru
- **Site:** https://vd.priv8.ru
- **Issues:** https://github.com/VD171/VDLiveUpdate/issues
- **GitHub:** [@VD171](https://github.com/VD171)
- **XDA-Developers:** [@VD171](https://xdaforums.com/m/vd171.4699873/)
- **Telegram:** [@VD_Priv8](https://t.me/VD_Priv8)
- **Channel:** [@Priv8_VD](https://t.me/Priv8_VD)
- **Discord:** [@VD.Priv8](https://discord.com/users/1296831918989639721)
- **E-mail:** vd.priv8@pm.me

Dołącz jasny opis oraz, jeśli to możliwe, manifest lub feed odtwarzający problem.
Odpowiemy tak szybko, jak to możliwe, i wymienimy Cię, jeśli sobie tego życzysz.

## Uwagi dotyczące zakresu

- Aktualizacje to bloby content-addressed oraz `manifest.json` podpisany za pomocą ed25519.
  Urządzenie weryfikuje podpis za pomocą wbudowanego `ed25519-mini` (bez openssl na
  urządzeniu), a każdy blob jest sprawdzany względem swojego `sha256` przed użyciem.
- Profil hardened (publiczne ustawienie domyślne) wymaga prawidłowego podpisu i blokuje
  downgrade. Wersja "początkowa" jest ograniczona od dołu przez `versionCode`
  zainstalowanego modułu (odczytany z `module.prop`), więc moduł nigdy nie jest cofany za
  feed.
- Korzeń zaufania (surowy klucz publiczny ed25519 w `keyring/` oraz pliki binarne w
  `verify/`) jest tylko-flash i nigdy nie jest rotowany przez sieć. Producent wyklucza go z
  feedu, a engine ignoruje każdą ścieżkę `vdlu/` w pobranym planie, więc wyciekły klucz
  podpisujący nie może podmienić weryfikatora ani klucza i utrwalić roota.
- Manifest prawidłowo podpisany dla innego modułu nie może zapisywać do katalogu innego
  modułu. Podpisane pole `module` musi być równe `MODID` na urządzeniu (sprawdzenie
  powiązania między modułami), a każdy zapis i usunięcie pozostaje ograniczone do katalogu
  modułu.
- Engine działa we własnym kontekście root modułu i nigdy go nie osłabia. Nie dodaje
  uprawnień i nie interpoluje żadnego pola manifestu do powłoki, każda wartość `path`,
  `sha256`, `mode` i `delete[]` jest walidowana jako wrogie dane wejściowe przed użyciem.
- Postawa jest fail-closed. Uszkodzona lub nieznana wartość `profile` nigdy nie przechodzi
  do akceptowania niepodpisanej zawartości (wszystko, co nie jest dokładnie `trusted`, jest
  traktowane jako `hardened`), a kopia zapasowa jest zapisywana przed nadpisaniem
  jakiegokolwiek pliku, więc nieudane apply nigdy nie niszczy zainstalowanej wersji.
- Zobacz [TRUST-MODEL.md](TRUST-MODEL.md), aby poznać pełny model zaufania, gwarancje
  fail-closed i szczegóły hardeningu.

<!-- doc-footer -->

---

> _Ta dokumentacja została wygenerowana za pomocą Claude (Anthropic) i jest utrzymywana przez VD171. Poprawki i ulepszenia są mile widziane, zobacz [CONTRIBUTING.md](CONTRIBUTING.md)._
