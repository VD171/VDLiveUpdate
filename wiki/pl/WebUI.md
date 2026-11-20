# WebUI

VDLU dostarcza opcjonalny, gotowy do wstawienia widget WebUI: mały panel "Updates" dla WebUI menedżera roota KernelSU lub APatch. Daje użytkownikowi przycisk Check, przycisk Update now, żywy toast postępu z anulowaniem, baner restartu i panel ustawień, a wszystko to bez dotykania terminala.

Jest to **czysty JavaScript**: bez frameworka, bez kroku budowania, bez CDN. Trzy pliki:

| Plik | Co to jest |
|---|---|
| `vdlu.js` | widget; udostępnia `window.VDLU` |
| `vdlu.css` | style dla toastu, banera i panelu (ciemny motyw, dziedziczy zmienne CSS hosta) |
| `demo.html` | samodzielna strona, która mockuje mostek urządzenia, aby cały UI działał w zwykłej przeglądarce |

Widget jest całkowicie opcjonalny. [[Engine]] działa doskonale samodzielnie z wyzwalaczy rozruchu; WebUI to tylko przyjazna twarz na jego wierzchu. Zobacz [[Quick Start]], aby podpiąć go do modułu.

---

## Jak UI rozmawia z silnikiem: mostek `ksu.exec`

Widget nigdy sam nie robi niczego uprzywilejowanego. Buduje polecenie powłoki i przekazuje je do mostka `ksu.exec` menedżera roota, który uruchamia je jako root i zwraca stdout / stderr / kod wyjścia. Wszystko, co panel pokazuje, jest odczytywane z plików, które zapisuje silnik.

Widget opakowuje ten mostek w pojedynczą funkcję `exec(cmd)`, która zwraca `Promise`:

- **rozwiązuje się (resolves)** z stdout, gdy polecenie zakończy się kodem 0
- **odrzuca się (rejects)** z stderr (lub `rc=N`) w przeciwnym razie

Każde polecenie niesie środowisko kontraktu, zmontowane przez widget:

```
VDLU_DIR=... MODULE_DIR=... MODID=... sh $MODULE_DIR/vdlu/update.sh <cmd>
```

Kilka konkretnych wywołań:

- **Rozpocznij aktualizację:** `update.sh run` jest uruchamiany w **tle** (`(... &)`), więc UI nigdy nie jest blokowany przez długie pobieranie.
- **Odczytaj postęp:** lekki poll (około raz na sekundę) `cat $VDLU_DIR/journal.json`.
- **Anuluj:** `touch $VDLU_DIR/cancel` (silnik zatrzymuje się w następnym bezpiecznym punkcie).
- **Konfiguracja:** odczyt i zapis `$VDLU_DIR/config` (key=value), zachowując kolejność i nieznane klucze oraz dotykając tylko kluczy, które użytkownik zmienił.

Jeśli host przekaże swoje własne helpery `exec`, `toast` i `confirm` do `init()`, widget kieruje przez własną zserializowaną kolejkę poleceń i wizualia hosta, więc wygląda i zachowuje się jak reszta tego WebUI. Jeśli zostaną pominięte, widget wraca do wywoływania `ksu.exec` bezpośrednio i wstrzykuje swój własny mini-toast.

---

## Toast postępu (z anulowaniem)

Gdy aktualizacja jest uruchomiona, widget pokazuje nieblokujący toast w rogu i polluje `journal.json`. Toast odzwierciedla maszynę stanów silnika:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

Renderuje pasek postępu plus linię `phase done/total - current file - bytes` i niesie przycisk **Cancel** przez cały czas. Stany końcowe każdy dostaje swoje własne potraktowanie:

- **DONE** -> zielony toast, "vX applied - all verified".
- **PENDING_REBOOT** -> zielony toast plus trwały baner restartu (poniżej).
- **ERROR** -> czerwony toast z przyczyną z `journal.error` lub stderr, oferujący Retry. Nigdy nie udaje sukcesu.
- **Cancelled** -> bursztynowy toast, "cancelled - N/M applied, resumable", oferujący **Resume**.
- **DEFERRED** -> łagodny niebieski toast informacyjny, "download deferred, waiting for the allowed network". To jest łagodne oczekiwanie polityki sieciowej, a nie błąd; wznawia się przy następnym check lub rozruchu we właściwej sieci.

Poll jest defensywny. Połowicznie zapisany dziennik (silnik zapisuje równolegle) jest ignorowany dla tego taktu, zamiast być błędnie sparsowany. Jeśli dziennik znika po tym, jak zaobserwowano postęp, oznacza to, że commit go wyczyścił: widget raportuje DONE. Jeśli dziennik jest nieobecny od początku przez 8 taktów, raportuje "no response". A jeśli dziennik zamarza na tych samych wartościach przez 20 taktów, widget sprawdza `lock.d` silnika: jeśli blokada żyje, to po prostu powolne pobieranie pojedynczego bloba i toast nadal czeka; jeśli blokada jest martwa, uruchomienie umarło w połowie, więc widget ujawnia błąd z przyciskiem Resume, zamiast kręcić się na "updating" w nieskończoność.

---

## Baner restartu

Niektórych plików nie da się podmienić na żywym systemie: `.so`, nakładki `/system`, `sepolicy.rule`. Silnik etapuje je i oznacza transakcję jako `PENDING_REBOOT`. Widget pokazuje wtedy **trwały baner u góry**: "Reboot to activate the new `.so` (vX)". Pozostaje, aż zetapowane pliki zostaną podmienione przy następnym rozruchu. Przy otwarciu WebUI baner jest ponownie oceniany z dziennika, więc użytkownik, który zamknie i ponownie otworzy UI, wciąż go widzi. Zobacz [[Reboot Handling]], aby dowiedzieć się, co dzieje się przy rozruchu.

Zauważ, że baner opiera się na stanie końcowym `PENDING_REBOOT`, a nie na fladze `reboot_pending` (która staje się prawdziwa, gdy tylko jakikolwiek `.so` wejdzie do planu). To powstrzymuje baner od pojawienia się w trakcie uruchomienia, zanim cokolwiek zostanie faktycznie zetapowane.

---

## Panel "Updates": niezależne przełączniki per-kategoria

`mountUpdatesPanel(el)` renderuje panel ustawień do pustego `<div>`, który dostarcza host. Ma trzy sekcje, a każdy element sterujący jest niezależny i zapisuje się samodzielnie:

**Actions**
- **Check for updates** -> uruchamia `check`, pokazuje wynik w linii (aktualne / nowsze niż kanał / aktualizacja dostępna z liczbą plików i tagiem reboot).
- **Update now** -> odpala `run` plus toast postępu.

**Automation** (niezależne przełączniki, każdy zapisywany do `config` w chwili przełączenia)
- **On WebUI open** (`auto_on_webui_open`) -> uruchom cichą aktualizację, gdy UI się otwiera.
- **On reboot** (`auto_on_reboot`) -> zastosuj w przed-zygote przy rozruchu.
- **Boot retry every (s)** i **Boot retry up to (min)** -> pola numeryczne do ponawiania pobrania manifestu, gdy urządzenie uruchamia się offline.

**Source**
- `source` (URL kanału), `channel` (stable / canary), `profile` (trusted / hardened) oraz select **Network** mapujący na `net_policy` (Wi-Fi + mobile / Wi-Fi only / mobile only).

Przełączniki i pola numeryczne zapisują się natychmiast i cofają się wizualnie, jeśli zapis się nie powiedzie. Pola tekstowe i select w sekcji Source oznaczają się jako brudne (dirty) i zapisują się razem po jawnym przyciskiem Save. Panel zawsze przepisuje tylko klucze, które użytkownik dotknął, więc wszelkie nieznane lub przyszłe klucze konfiguracji są zachowywane.

### Zachowanie automatycznego otwarcia

`onWebUIOpen()` jest wywoływany przy ładowaniu hosta. Ocenia dziennik (pokazując baner restartu lub oferując Resume dla niekońcowej transakcji pozostawionej przez poprzednią sesję), a następnie, jeśli `auto_on_webui_open=1`, uruchamia **ciche** `check()` najpierw. Trwały toast postępu i faktyczny `run` odpalają się tylko wtedy, gdy jest realne pobranie do wykonania (`update && fetch > 0`). Jeśli urządzenie jest aktualne lub wyprzedza kanał, wynik pokazuje się w linii w panelu i żaden toast nie pozostaje na ekranie, więc automatyczna aktualizacja jest tak samo nieinwazyjna jak ręczny przycisk.

---

## i18n (ciągi per-język)

Każdy ciąg UI domyślnie jest po **angielsku**, co jest neutralnym wyborem dla publicznych wielojęzycznych modułów. Pełna mapa kluczy znajduje się w obiekcie `DEFAULT_I18N` w `vdlu.js` (udostępniona także jako `VDLU.i18n`). Host nadpisuje dowolny podzbiór kluczy, przekazując mapę do `init({ i18n: ... })`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>
  VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x',
              i18n: window.VDLU_I18N_PT_BR });
</script>
```

- **Częściowa** mapa jest w porządku: każdy brakujący klucz wraca do angielskiej wartości domyślnej.
- Etykiety faz i stanów używają kluczy `ph_<phase>` i `st_<STATE>`; reszta to płaskie klucze jak `cancel`, `updateNow`.
- Przepracowane tłumaczenie (`i18n/pt-BR.js`) dostarczane jest jako szablon; nowy język to po prostu plik `i18n/<lang>.js` w tym samym kształcie lub host buduje mapę z własnego systemu i18n.

---

## demo.html: uruchom UI bez urządzenia

`demo.html` mockuje mostek `ksu.exec`, aby dokładnie te same `vdlu.js` i `vdlu.css` działały w zwykłej przeglądarce, bez roota i bez telefonu:

```sh
xdg-open webui/demo.html
```

Mock symuluje `update.sh` i ewoluujący `journal.json`, a jego przyciski przełączają między scenariuszami: aktualizacja na żywo aż do DONE, zakończenie `reboot_pending`, błąd w połowie i anulowalne uruchomienie. To najszybszy sposób, aby zobaczyć i iterować UI, i to jest to, co sprawdzasz, zanim wbudujesz widget do modułu.

---

## Podpinanie do modułu (wyzwalacz otwarcia WebUI)

Host `index.html` ładuje dwa pliki i wywołuje trzy funkcje:

```html
<link rel="stylesheet" href="vdlu.css">
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,   // $MODULE_DIR (where the engine is vendored)
    vdluDir:   '/data/adb/' + MODID + '/vdlu',  // $VDLU_DIR  (Tier-2 state, outside the module dir)
    modid:     MODID,
    module:    'Demo',        // friendly name shown in the toast (default: modid)
    exec:   ex,               // optional: the host's ksu.exec wrapper
    toast:  toast,            // optional: the host's transient toast
    confirm: askConfirm       // optional: the host's modal
  });

  VDLU.onWebUIOpen();                          // the WebUI-open trigger: banner + auto-update eval
  VDLU.mountUpdatesPanel('b-updates');         // render the "Updates" tab into an empty div
</script>
```

Host musi tylko dostarczyć ścieżki Tier-2 i przydzielić jeden pusty `<div>` dla panelu; toast i baner są wstrzykiwane do `document.body` przez widget. `onWebUIOpen()` to wyzwalacz otwarcia WebUI: to on ocenia baner restartu, oferuje Resume na przerwanej transakcji i uruchamia ciche automatyczne aktualizacje, gdy ustawione jest `auto_on_webui_open`.

### Pojedyncze źródło, ponownie wbudowane bajt w bajt

`vdlu.js` i `vdlu.css` to **kopia kanoniczna**. Moduł, który osadza widget, ponownie wbudowuje te pliki niezmienione do swojego `webroot/`; nigdy nie edytuje swojej własnej kopii w miejscu. Nowa funkcja rodzi się w plikach kanonicznych i spływa w dół przez ponowne wbudowanie. Edytowanie wbudowanej kopii produkuje cichą rozbieżność (zdarzało się: przestarzała kopia nie miała `net_policy`, toastu DEFERRED i pól ponawiania przy rozruchu). Strażnik parytetu w drzewie źródłowym znajduje każdą kopię i flaguje lub ponownie wbudowuje te, które rozchodzą się, obejmując tylko widget; keyring ma swoją własną kadencję weryfikuj-nie-kopiuj.

---

### Publiczne API (`window.VDLU`)

| Funkcja | Robi |
|---|---|
| `init(opts)` | konfiguruje widget; zwraca `window.VDLU` |
| `onWebUIOpen()` | wywołaj przy ładowaniu: baner, oferta Resume i ciche automatyczne aktualizacje |
| `mountUpdatesPanel(el)` | renderuje panel Updates do `el` (id string lub element) |
| `check()` | uruchamia `update.sh check`; `Promise<{update, from, to, fetch, reboot}>` |
| `startUpdate()` | odpala `run` w tle plus toast postępu z Cancel |
| `cancel()` | tworzy `$VDLU_DIR/cancel` (silnik zatrzymuje się w bezpiecznym punkcie) |
| `resume()` | wznawia bieżącą transakcję plus toast |
| `refreshBanner()` | ponownie ocenia trwały baner oczekującego restartu |

---

Zobacz także: [[Engine]], aby poznać polecenia, którymi steruje widget, [[Quick Start]], aby poznać pełne kroki wdrożenia, oraz [[Reboot Handling]], aby dowiedzieć się, na co czeka baner.
