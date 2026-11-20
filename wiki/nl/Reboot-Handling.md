# Reboot Handling

Het hele punt van VDLU is een module bijwerken zonder die opnieuw te flashen, en, waar mogelijk, zonder überhaupt te herstarten. De meeste bestanden in een module kunnen worden vervangen terwijl het apparaat draait. Een paar kunnen dat echt niet, omdat de kernel of het zygote-proces ze al heeft gemapt en een wijziging pas bij de volgende boot zal opmerken.

De taak van VDLU is die twee groepen automatisch uit elkaar te houden, alles wat het veilig kan **live** toepassen, en alleen de echt boot-gebonden bestanden uitstellen tot een herstart die het duidelijk markeert. Deze pagina legt uit hoe.

Voor de engine-mechanica hieronder, zie [[Engine]]. Voor het grote plaatje, zie [[Architecture]].

## Waarom niet gewoon elke keer herstarten

Een herstart is het duurste wat een update van iemand kan vragen. Het onderbreekt waar diegene mee bezig is, het duurt een minuut of meer, en het leert mensen updates te vrezen. Een goede incrementele updater zou onzichtbaar moeten aanvoelen: je tikt op update, een paar bestanden veranderen onder het draaiende systeem, en je bent al op de nieuwe versie.

Dus VDLU keert de gebruikelijke aanname om. De standaard is live. Een bestand wordt pas tot een herstart uitgesteld wanneer het aantoonbaar een van de kernel- of zygote-gebonden soorten is, en zelfs dan wacht alleen dat bestand. Alles eromheen updatet nog steeds direct.

## De drie klassen

Elk bestand in de feed krijgt een class toegewezen. De producer kan die expliciet in het manifest zetten, maar in de praktijk wordt de class afgeleid van het pad, en de engine zal een bestand alleen ooit naar `reboot` opwaarderen, nooit afwaarderen naar `live`. De klassen zijn:

**LIVE** is het veelvoorkomende geval: web-UI-assets, binaries, scripts die op aanvraag worden gelezen, configbestanden, `module.prop`, en al het andere dat niet door de onderstaande regels wordt gematcht. Een live bestand wordt geback-upt en dan atomair over het doel hernoemd terwijl het systeem draait. Geen herstart, en de wijziging is van kracht op het moment dat de rename landt.

**SOFT** zijn de eigen levenscyclusscripts van de module: `service.sh`, `post-fs-data.sh`, en `boot-completed.sh`. Deze worden live toegepast precies zoals LIVE-bestanden, zodat de nieuwe kopie al op schijf staat. De reden dat ze hun eigen class krijgen, is dat het draaiende systeem de oude kopie deze boot al heeft uitgevoerd; de nieuwe draait simpelweg de volgende boot, zonder fasering en zonder banner. Er is niets uit te stellen, slechts een natuurlijke overdracht.

**REBOOT-hard** is de kleine set die niet onder een draaiend systeem kan veranderen:

- native libraries, `*.so` (alles onder een `zygisk/`-pad), omdat zygote ze bij het opstarten in elke app mapt;
- `/system`-overlay-bestanden, omdat de overlay bij boot wordt gemount;
- `sepolicy.rule`-bestanden, omdat SELinux-beleid vroeg wordt geladen.

Een REBOOT-hard-bestand wordt nooit over zijn live inode geschreven terwijl het systeem draait. Een `.so` overschrijven die zygote al heeft gemapt, is hoe je crashes en inconsistente toestand krijgt. In plaats daarvan wordt de nieuwe inhoud **gefaseerd** naast de toestandsdirectory en bij de volgende boot ingewisseld, voordat iets die kan mappen.

## Pad naar class, in één oogopslag

De engine leidt de class als volgt af van het pad:

| Padpatroon | Class | Toegepast |
|---|---|---|
| `zygisk/**`, `**/zygisk/**` (de `.so`-bestanden) | REBOOT-hard | gefaseerd, pre-zygote omgewisseld bij boot |
| `system/**` (overlay) | REBOOT-hard | gefaseerd, omgewisseld bij boot |
| `*.rule` (sepolicy) | REBOOT-hard | gefaseerd, omgewisseld bij boot |
| `service.sh`, `post-fs-data.sh`, `boot-completed.sh` | SOFT | live geschreven, draait volgende boot |
| `webroot/**`, `bin/**`, `lib/**`, configs, `module.prop`, al het andere | LIVE | live geschreven, direct van kracht |

Het manifest kan een expliciete `class` per bestand dragen, maar de afgeleide class fungeert als bodem: als een bestand er door zijn pad REBOOT-hard uitziet, wordt het als REBOOT-hard behandeld, zelfs als het manifest iets anders zegt. Dit voorkomt dat een verkeerd gelabelde feed ooit een `.so` probeert te hot-swappen.

## Hoe een run beide groepen tegelijk afhandelt

Tijdens een normale `run` (de DIFF-naar-FETCH-naar-APPLY-naar-COMMIT-cyclus beschreven in [[Engine]]), worden de twee groepen in dezelfde transactie afgehandeld:

```
run:
  LIVE + SOFT  --> backup -> write .vdlu-tmp -> verify -> atomic rename   (effective now)
  REBOOT-hard  --> materialize into staged/<path>.vdlu-new                (live inode untouched)

  re-hash every LIVE + SOFT file
       |
       +-- nothing staged  --> DONE
       +-- something staged --> PENDING_REBOOT  (reboot banner in the WebUI)
```

Dus na een run die een `.so` aanraakte, ben je al op de nieuwe versie voor elk live bestand, en alleen de gefaseerde stukken wachten. Het journal rapporteert `reboot_pending`, en de WebUI toont een aanhoudende banner die uitnodigt tot een herstart om de gefaseerde bestanden te activeren. Er is geen valse "done": een run met gefaseerde bestanden eindigt in `PENDING_REBOOT`, niet `DONE`.

## De swap bij boot

De gefaseerde bestanden worden toegepast door het `boot`-commando, dat de host-module in `post-fs-data.sh` bedraadt zodat het synchroon en **pre-zygote** draait, voordat enig proces de nieuwe `.so` kan mappen.

`boot` doet een `resume` (om een onderbroken fase af te maken) en dan de swap. Voor elk gefaseerd REBOOT-hard-bestand:

1. bevestigt het dat het gefaseerde pad binnen de moduledirectory blijft (een containment-controle);
2. herhasht het `staged/<path>.vdlu-new` tegen de manifest-hash;
3. back-upt het het huidige live bestand;
4. `mv -f` het gefaseerde bestand over het live en `chmod`t het;
5. herhasht het het bestand dat nu op zijn plaats staat, om te bevestigen dat de swap correct landde;
6. markeert het als toegepast.

Pas wanneer elk gefaseerd bestand is omgewisseld en herverifieerd, sluit de transactie van `PENDING_REBOOT` naar `DONE`. Als een stap mislukt, legt het journal de fout vast en behoudt de module zijn vorige bestanden; niets blijft half-omgewisseld achter.

Omdat de swap een reeks herhashes en atomaire renames is, is het draaien van `boot` veilig zelfs als het de vorige keer werd onderbroken. Het pakt simpelweg de gefaseerde bestanden weer op.

## auto_on_reboot

Fasering is slechts de helft van een herstartvrij gevoel; de andere helft is dat de gebruiker nooit zou moeten hoeven onthouden om de swap te draaien. Met `auto_on_reboot=1` in de config roept de `post-fs-data.sh` van de host-module `update.sh boot` aan bij elke boot. Dat betekent:

- als een transactie pending reboot is, worden de gefaseerde bestanden automatisch ingewisseld voordat zygote start, en de gebruiker bevindt zich simpelweg volledig op de nieuwe versie;
- als er niets in afwachting is, kan `boot` een verse cyclus draaien en alles toepassen, inclusief een `.so`, in die ene boot, aangezien het al pre-zygote draait.

Met andere woorden, een gefaseerde `.so` kost de gebruiker niets boven een herstart die die toch al ging doen. Ze hoeven de tweede keer nergens op te tikken.

## Offline bij boot, zonder de batterij leeg te trekken

Soms wil `boot` de feed controleren maar heeft het apparaat nog geen netwerk. VDLU kan erop wachten, geduldig en goedkoop, geregeld door `boot_retry_minutes` (0 schakelt het uit). Het wachten is bewust batterijveilig:

- tussen pogingen `sleep`t het simpelweg, wat bevriest in deep sleep, zodat het apparaat normaal slaapt en de retry pas hervat zodra het apparaat al wakker is;
- het houdt geen wakelock en houdt de engine-lock niet vast tijdens het wachten, zodat een handmatige run nooit wordt geblokkeerd;
- voor elke poging controleert het of het netwerk is toegestaan met een kernel-route-opzoeking die geen pakket verstuurt en de radio niet wekt;
- het probeert nooit een deterministische fout opnieuw zoals een slechte handtekening of een geblokkeerde downgrade, alleen een echte netwerk-afwezig-conditie.

De manifest-check zelf blijft gratis op elk netwerk, zodat je altijd leert dat een update bestaat; alleen de download wacht tot aan het netwerkbeleid is voldaan, en stelt netjes uit in plaats van te falen.

## Zie ook

- [[Engine]]: de transactie, de apply-per-class-logica, en het `boot`-commando volledig.
- [[Architecture]]: waar de engine zit tussen de producer en WebUI.
