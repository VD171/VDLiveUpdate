# Reboot Handling

Cały sens VDLU to aktualizowanie modułu bez ponownego flashowania go i, gdziekolwiek to możliwe, bez ponownego uruchamiania w ogóle. Większość plików w module można zastąpić, gdy urządzenie działa. Kilka naprawdę nie można, ponieważ jądro lub proces zygote już je zmapował i nie zauważy zmiany aż do następnego rozruchu.

Zadaniem VDLU jest automatycznie rozróżnić te dwie grupy, zastosować wszystko, co bezpiecznie może, **na żywo**, i odroczyć tylko naprawdę związane z rozruchem pliki do ponownego uruchomienia, które wyraźnie flaguje. Ta strona wyjaśnia jak.

Aby poznać mechanikę silnika pod tym, zobacz [[Engine]]. Aby poznać całościowy obraz, zobacz [[Architecture]].

## Dlaczego nie po prostu restartować za każdym razem

Ponowne uruchomienie to najdroższa rzecz, o którą aktualizacja może poprosić człowieka. Przerywa to, co właśnie robi, zajmuje minutę lub więcej i uczy ludzi obawiać się aktualizacji. Dobry przyrostowy aktualizator powinien czuć się niewidzialny: stukasz aktualizuj, kilka plików zmienia się pod działającym systemem i już jesteś na nowej wersji.

Więc VDLU odwraca zwykłe założenie. Domyślnie jest na żywo. Plik jest odraczany do ponownego uruchomienia tylko wtedy, gdy jest dowodnie jednym z rodzajów związanych z jądrem lub zygote, a nawet wtedy tylko ten plik czeka. Wszystko wokół niego nadal aktualizuje się natychmiast.

## Trzy klasy

Każdy plik w kanale otrzymuje klasę. Producent może ustawić ją jawnie w manifeście, ale w praktyce klasa jest wyprowadzana ze ścieżki, a silnik zawsze tylko podnosi plik w kierunku `reboot`, nigdy nie obniża go w kierunku `live`. Klasy to:

**LIVE** to przypadek powszechny: zasoby web UI, pliki binarne, skrypty czytane na żądanie, pliki konfiguracyjne, `module.prop` i wszystko inne niepasujące do reguł poniżej. Plik live jest kopiowany, a następnie atomowo przemianowywany nad celem, gdy system działa. Bez ponownego uruchomienia, a zmiana jest w mocy w chwili, gdy `rename` ląduje.

**SOFT** to własne skrypty cyklu życia modułu: `service.sh`, `post-fs-data.sh` i `boot-completed.sh`. Są one stosowane na żywo dokładnie jak pliki LIVE, więc nowa kopia jest już na dysku. Powodem, dla którego dostają własną klasę, jest to, że działający system już wykonał starą kopię w tym rozruchu; nowa po prostu uruchomi się następnym rozruchem, bez etapowania i bez banera. Nie ma nic do odroczenia, tylko naturalne przekazanie.

**REBOOT-hard** to mały zestaw, który nie może zmienić się pod działającym systemem:

- biblioteki natywne, `*.so` (cokolwiek pod ścieżką `zygisk/`), ponieważ zygote mapuje je do każdej aplikacji przy starcie;
- pliki nakładki `/system`, ponieważ nakładka jest montowana przy rozruchu;
- pliki `sepolicy.rule`, ponieważ polityka SELinux jest ładowana wcześnie.

Plik REBOOT-hard nigdy nie jest zapisywany nad swoim żywym inode, gdy system działa. Nadpisanie `.so`, które zygote już zmapował, to sposób na uzyskanie awarii i niespójnego stanu. Zamiast tego nowa treść jest **etapowana** obok katalogu stanu i podmieniana przy następnym rozruchu, zanim cokolwiek może ją zmapować.

## Ścieżka do klasy, w skrócie

Silnik wyprowadza klasę ze ścieżki tak:

| Wzorzec ścieżki | Klasa | Stosowane |
|---|---|---|
| `zygisk/**`, `**/zygisk/**` (pliki `.so`) | REBOOT-hard | etapowane, podmieniane przed-zygote przy rozruchu |
| `system/**` (nakładka) | REBOOT-hard | etapowane, podmieniane przy rozruchu |
| `*.rule` (sepolicy) | REBOOT-hard | etapowane, podmieniane przy rozruchu |
| `service.sh`, `post-fs-data.sh`, `boot-completed.sh` | SOFT | zapisywane na żywo, uruchamiane następnym rozruchem |
| `webroot/**`, `bin/**`, `lib/**`, konfiguracje, `module.prop`, wszystko inne | LIVE | zapisywane na żywo, skuteczne natychmiast |

Manifest może nieść jawną `class` per plik, ale wyprowadzona klasa działa jako podłoga: jeśli plik wygląda na REBOOT-hard po swojej ścieżce, jest traktowany jako REBOOT-hard, nawet jeśli manifest mówi inaczej. To powstrzymuje błędnie oznaczony kanał od kiedykolwiek próby gorącej podmiany `.so`.

## Jak uruchomienie obsługuje obie grupy naraz

Podczas normalnego `run` (cyklu DIFF do FETCH do APPLY do COMMIT opisanego w [[Engine]]) obie grupy są obsługiwane w tej samej transakcji:

```
run:
  LIVE + SOFT  --> backup -> write .vdlu-tmp -> verify -> atomic rename   (effective now)
  REBOOT-hard  --> materialize into staged/<path>.vdlu-new                (live inode untouched)

  re-hash every LIVE + SOFT file
       |
       +-- nothing staged  --> DONE
       +-- something staged --> PENDING_REBOOT  (reboot banner in the WebUI)
```

Więc po uruchomieniu, które dotknęło `.so`, jesteś już na nowej wersji dla każdego żywego pliku, a tylko zetapowane kawałki czekają. Dziennik raportuje `reboot_pending`, a WebUI pokazuje trwały baner zapraszający do ponownego uruchomienia w celu aktywacji zetapowanych plików. Nie ma fałszywego "done": uruchomienie z zetapowanymi plikami kończy się w `PENDING_REBOOT`, a nie `DONE`.

## Podmiana przy rozruchu

Zetapowane pliki są stosowane przez polecenie `boot`, które moduł hosta podpina do `post-fs-data.sh`, aby działało synchronicznie i **przed-zygote**, zanim jakikolwiek proces może zmapować nowy `.so`.

`boot` wykonuje `resume` (aby dokończyć dowolną przerwaną fazę), a następnie podmianę. Dla każdego zetapowanego pliku REBOOT-hard:

1. potwierdza, że zetapowana ścieżka pozostaje wewnątrz katalogu modułu (kontrola zawierania);
2. ponownie haszuje `staged/<path>.vdlu-new` względem skrótu manifestu;
3. tworzy kopię zapasową bieżącego żywego pliku;
4. `mv -f` zetapowany plik nad żywy i wykonuje `chmod`;
5. ponownie haszuje plik teraz na miejscu, aby potwierdzić, że podmiana wylądowała poprawnie;
6. oznacza go jako zastosowany.

Dopiero gdy każdy zetapowany plik został podmieniony i ponownie zweryfikowany, transakcja zamyka się z `PENDING_REBOOT` do `DONE`. Jeśli jakikolwiek krok się nie powiedzie, dziennik zapisuje błąd, a moduł zachowuje swoje poprzednie pliki; nic nie jest pozostawione połowicznie podmienione.

Ponieważ podmiana to sekwencja ponownych haszowań i atomowych przemianowań, uruchomienie `boot` jest bezpieczne, nawet jeśli zostało przerwane ostatnim razem. Po prostu podejmuje zetapowane pliki z powrotem.

## auto_on_reboot

Etapowanie to tylko połowa odczucia braku ponownego uruchamiania; druga połowa to to, że użytkownik nigdy nie powinien musieć pamiętać, aby uruchomić podmianę. Z `auto_on_reboot=1` w konfiguracji `post-fs-data.sh` modułu hosta wywołuje `update.sh boot` przy każdym rozruchu. To oznacza:

- jeśli transakcja oczekuje na restart, zetapowane pliki są podmieniane automatycznie przed startem zygote, a użytkownik po prostu zastaje siebie w pełni na nowej wersji;
- jeśli nic nie oczekuje, `boot` może uruchomić świeży cykl i zastosować wszystko, łącznie z `.so`, w tym jednym rozruchu, ponieważ już działa przed-zygote.

Innymi słowy, zetapowany `.so` nie kosztuje użytkownika nic poza ponownym uruchomieniem, które i tak miał zamiar zrobić. Nie musi stukać niczego drugi raz.

## Offline przy rozruchu, bez drenażu baterii

Czasem `boot` chce sprawdzić kanał, ale urządzenie nie ma jeszcze sieci. VDLU może na nią poczekać, cierpliwie i tanio, sterowane przez `boot_retry_minutes` (0 to wyłącza). Oczekiwanie jest celowo bezpieczne dla baterii:

- między próbami po prostu wykonuje `sleep`, który zamraża w głębokim śnie, więc urządzenie śpi normalnie, a ponawianie wznawia się dopiero, gdy urządzenie jest już obudzone;
- nie trzyma wakelock i nie trzyma blokady silnika podczas oczekiwania, więc ręczne uruchomienie nigdy nie jest blokowane;
- przed każdą próbą sprawdza, czy sieć jest dozwolona, za pomocą wyszukiwania trasy w jądrze, które nie wysyła żadnego pakietu i nie budzi radia;
- nigdy nie ponawia deterministycznego niepowodzenia, takiego jak zły podpis lub zablokowane cofnięcie wersji, tylko prawdziwy warunek braku sieci.

Samo sprawdzenie manifestu pozostaje darmowe w każdej sieci, więc zawsze dowiadujesz się o istnieniu aktualizacji; tylko pobieranie czeka na spełnienie polityki sieciowej, odraczając się czysto, zamiast błędem.

## Zobacz także

- [[Engine]]: transakcja, logika stosowania według klasy i polecenie `boot` w całości.
- [[Architecture]]: gdzie silnik siedzi wśród producenta i WebUI.
