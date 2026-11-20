# Contributing

Wkład jest mile widziany. VDLU to bezflashowy, przyrostowy silnik samoaktualizacji
wbudowany w moduły KernelSU / APatch / Magisk. Ta strona to praktyczny deweloperski
przepływ pracy; aby poznać, jak elementy do siebie pasują, przeczytaj najpierw [[Architecture]], [[Engine]] i
[[Producer]].

## Nic się nie kompiluje

VDLU to skrypty (POSIX sh, trochę Pythona po stronie wydania, czysty JS dla
WebUI), więc nie ma kroku budowania. Weryfikujesz zmianę, uruchamiając potok
od początku do końca i statycznie sprawdzając każdy element.

## Najpierw kontrakt szwu

Kontrakt interfejsu między komponentami (sygnatury CLI, nazwy plików i
klucze JSON współdzielone przez silnik, producenta i WebUI) to **prawo
konwergencji**. Traktuj go jako niezmienny. Jeśli Twoja zmiana dotyka szwu
producent-do-silnika (schemat manifestu, schemat dziennika, klucze konfiguracji, reguła
podpisu/kanonikalizacji), **najpierw wyrównaj kontrakt interfejsu**, potem
zmień kod po obu stronach, aby pasował. Zmiana po jednej stronie szwu bez
drugiej po cichu łamie adopterów. Zobacz [[Producer]], aby poznać regułę kanonikalizacji,
na którą podpisujący i weryfikator muszą zgodzić się bajt w bajt.

## Testuj od początku do końca przed PR

Uruchom producenta i silnik razem na jednorazowym drzewie, w ten sam sposób, w jaki robi to
wydanie adoptera:

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

Następnie statycznie sprawdź każdy komponent:

```sh
sh -n engine/*.sh            # POSIX sh syntax, must pass
node --check webui/vdlu.js   # WebUI JS syntax
```

I otwórz `webui/demo.html` w przeglądarce: mockuje mostek menedżera roota
(`ksu.exec`), więc możesz przećwiczyć panel Updates, toast postępu, anulowanie
i baner restartu bez urządzenia. Zobacz [[WebUI]].

## Zasady domu

- **POSIX sh na urządzeniu.** Bez konstrukcji bash poza `local` i bez `jq`. Musi
  działać na toybox / busybox.
- **Bezpieczeństwo jest nienegocjowalne.** Każde pole manifestu to wrogie wejście;
  `validate_plan()` pozostaje fail-closed, a prywatny klucz podpisujący nigdy nie dotyka
  CI ani urządzenia. Nie rozluźniaj kontroli, by test przeszedł.
- **Rygor przy niepowodzeniu.** Utrzymaj transakcję wznawialną: nic nie raportuje "done"
  bez zgodnego ponownego obliczenia skrótu, nic nie jest nadpisywane bez kopii zapasowej, a
  zastosowania pozostają atomowe.
- **Zawsze jakość wydania.** Utrzymuj komentarze zwięzłe; bez zbędnych komentarzy.
- **Jedna logiczna zmiana na PR.** Powiedz, co się zmieniło i dlaczego.

## Zgłaszanie problemów

Otwórz zgłoszenie opisujące, co zrobiłeś, czego oczekiwałeś i co się stało.
Dla błędu dołącz id modułu, profil źródła (`hardened` lub `trusted`),
polecenie `update.sh`, które uruchomiłeś, i odpowiedni `journal.json` (zapisuje
fazę, stan i błąd). Dla funkcji powiedz, którego komponentu dotyczy (silnik,
producent lub WebUI), aby wpływ na szew był jasny z góry.
