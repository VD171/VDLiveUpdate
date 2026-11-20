# Omstartshantering

Hela poängen med VDLU är att uppdatera en modul utan att flasha om den, och, där det är möjligt, utan att starta om alls. De flesta filer i en modul kan ersättas medan enheten körs. Några få kan verkligen inte, eftersom kärnan eller zygote-processen redan har mappat dem och inte märker en ändring förrän nästa boot.

VDLU:s uppgift är att skilja de två grupperna åt automatiskt, tillämpa allt den säkert kan **i realtid**, och skjuta upp bara de verkligt bootbundna filerna till en omstart som den tydligt flaggar. Denna sida förklarar hur.

För motormekaniken under detta, se [[Engine]]. För helhetsbilden, se [[Architecture]].

## Varför inte bara starta om varje gång

En omstart är det dyraste en uppdatering kan be någon om. Den avbryter vad de än gör, den tar en minut eller mer, och den tränar folk att frukta uppdateringar. En bra inkrementell uppdaterare bör kännas osynlig: du trycker uppdatera, några filer ändras under det körande systemet, och du är redan på den nya versionen.

Så VDLU inverterar det vanliga antagandet. Standard är i realtid. En fil skjuts upp till en omstart bara när den bevisligen är en av de kärn- eller zygote-bundna sorterna, och även då väntar bara den filen. Allt runt den uppdateras fortfarande omedelbart.

## De tre klasserna

Varje fil i flödet tilldelas en klass. Producenten kan sätta den explicit i manifestet, men i praktiken härleds klassen från sökvägen, och motorn kommer bara någonsin att uppgradera en fil mot `reboot`, aldrig nedgradera den mot `live`. Klasserna är:

**LIVE** är det vanliga fallet: webb-UI-tillgångar, binärer, skript som läses på begäran, konfigurationsfiler, `module.prop`, och allt annat som inte matchas av reglerna nedan. En live-fil säkerhetskopieras och döps sedan om atomärt över målet medan systemet körs. Ingen omstart, och ändringen är i kraft i det ögonblick omdöpningen landar.

**SOFT** är modulens egna livscykelskript: `service.sh`, `post-fs-data.sh` och `boot-completed.sh`. Dessa tillämpas i realtid precis som LIVE-filer, så den nya kopian är redan på disk. Anledningen till att de får sin egen klass är att det körande systemet redan har kört den gamla kopian denna boot; den nya körs helt enkelt nästa boot, utan förberedelse och utan banner. Det finns inget att skjuta upp, bara en naturlig överlämning.

**REBOOT-hard** är den lilla uppsättningen som inte kan ändras under ett körande system:

- native-bibliotek, `*.so` (allt under en `zygisk/`-sökväg), eftersom zygote mappar dem in i varje app vid start;
- `/system`-överläggsfiler, eftersom överlägget monteras vid boot;
- `sepolicy.rule`-filer, eftersom SELinux-policyn laddas tidigt.

En REBOOT-hard-fil skrivs aldrig över sin aktiva inod medan systemet är uppe. Att skriva över en `.so` som zygote redan har mappat är hur du får krascher och inkonsekvent tillstånd. I stället **förbereds** det nya innehållet bredvid tillståndskatalogen och byts in vid nästa boot, innan något kan mappa det.

## Sökväg till klass, på ett ögonkast

Motorn härleder klassen från sökvägen så här:

| Sökvägsmönster | Klass | Tillämpas |
|---|---|---|
| `zygisk/**`, `**/zygisk/**` (`.so`-filerna) | REBOOT-hard | förberedd, bytt före zygote vid boot |
| `system/**` (överlägg) | REBOOT-hard | förberedd, bytt vid boot |
| `*.rule` (sepolicy) | REBOOT-hard | förberedd, bytt vid boot |
| `service.sh`, `post-fs-data.sh`, `boot-completed.sh` | SOFT | skriven i realtid, körs nästa boot |
| `webroot/**`, `bin/**`, `lib/**`, konfigurationer, `module.prop`, allt annat | LIVE | skriven i realtid, i kraft omedelbart |

Manifestet kan bära en explicit `class` per fil, men den härledda klassen fungerar som ett golv: om en fil ser REBOOT-hard ut efter sin sökväg behandlas den som REBOOT-hard även om manifestet säger annat. Detta håller ett felmärkt flöde från att någonsin försöka varmbyta en `.so`.

## Hur en körning hanterar båda grupperna samtidigt

Under en normal `run` (DIFF till FETCH till APPLY till COMMIT-cykeln beskriven i [[Engine]]) hanteras de två grupperna i samma transaktion:

```
run:
  LIVE + SOFT  --> backup -> write .vdlu-tmp -> verify -> atomic rename   (effective now)
  REBOOT-hard  --> materialize into staged/<path>.vdlu-new                (live inode untouched)

  re-hash every LIVE + SOFT file
       |
       +-- nothing staged  --> DONE
       +-- something staged --> PENDING_REBOOT  (reboot banner in the WebUI)
```

Så efter en körning som vidrörde en `.so` är du redan på den nya versionen för varje live-fil, och bara de förberedda bitarna väntar. Journalen rapporterar `reboot_pending`, och WebUI visar en bestående banner som inbjuder till en omstart för att aktivera de förberedda filerna. Det finns inget falskt "done": en körning med förberedda filer slutar i `PENDING_REBOOT`, inte `DONE`.

## Bytet vid boot

De förberedda filerna tillämpas av `boot`-kommandot, som värdmodulen kopplar in i `post-fs-data.sh` så att det körs synkront och **före zygote**, innan någon process kan mappa den nya `.so`.

`boot` gör ett `resume` (för att avsluta någon avbruten fas) och sedan bytet. För varje förberedd REBOOT-hard-fil gör den:

1. bekräftar att den förberedda sökvägen stannar inuti modulkatalogen (en inneslutningskontroll);
2. omhashar `staged/<path>.vdlu-new` mot manifesthashen;
3. säkerhetskopierar den aktuella live-filen;
4. `mv -f` den förberedda filen över den aktiva och `chmod`:ar den;
5. omhashar filen nu på plats, för att bekräfta att bytet landade korrekt;
6. markerar den som tillämpad.

Bara när varje förberedd fil har bytts och omverifierats stänger transaktionen från `PENDING_REBOOT` till `DONE`. Om något steg misslyckas registrerar journalen felet och modulen behåller sina tidigare filer; inget lämnas halvbytt.

Eftersom bytet är en sekvens av omhashningar och atomära omdöpningar är det säkert att köra `boot` även om det avbröts förra gången. Den plockar helt enkelt upp de förberedda filerna igen.

## auto_on_reboot

Förberedelse är bara halva en omstartsfri känsla; den andra halvan är att användaren aldrig ska behöva komma ihåg att köra bytet. Med `auto_on_reboot=1` i konfigurationen anropar värdmodulens `post-fs-data.sh` `update.sh boot` vid varje boot. Det betyder:

- om en transaktion väntar på omstart byts de förberedda filerna in automatiskt innan zygote startar, och användaren finner sig helt enkelt helt på den nya versionen;
- om inget väntar kan `boot` köra en ny cykel och tillämpa allt, inklusive en `.so`, i den enda booten, eftersom den redan körs före zygote.

Med andra ord kostar en förberedd `.so` användaren inget utöver en omstart de ändå tänkte göra. De behöver inte trycka på något den andra gången.

## Offline vid boot, utan att dränera batteriet

Ibland vill `boot` kontrollera flödet men enheten har inget nätverk ännu. VDLU kan vänta på det, tålmodigt och billigt, styrt av `boot_retry_minutes` (0 stänger av det). Väntandet är avsiktligt batterisäkert:

- mellan försöken gör den helt enkelt `sleep`, vilket fryser i djupsömn, så att enheten sover normalt och återförsöket återupptas bara när enheten redan är vaken;
- den håller ingen wakelock och håller inte motorlåset medan den väntar, så en manuell körning blockeras aldrig;
- före varje försök kontrollerar den om nätverket är tillåtet med en kärnruttsuppslagning som inte skickar något paket och inte väcker radion;
- den försöker aldrig om ett deterministiskt fel som en dålig signatur eller en blockerad nedgradering, bara ett genuint nätverk-frånvarande-tillstånd.

Manifestkontrollen själv förblir gratis på vilket nätverk som helst, så du får alltid veta att en uppdatering finns; bara nedladdningen väntar på att nätverkspolicyn ska uppfyllas, och skjuts upp rent i stället för att ge fel.

## Se även

- [[Engine]]: transaktionen, tillämpa-efter-klass-logiken och `boot`-kommandot i sin helhet.
- [[Architecture]]: var motorn sitter bland producenten och WebUI.
