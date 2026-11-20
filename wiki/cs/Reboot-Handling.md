# Reboot Handling

Celým smyslem VDLU je aktualizovat modul bez jeho znovu-flashování a, kdykoli je to možné, bez restartu vůbec. Většinu souborů v modulu lze nahradit, zatímco zařízení běží. Pár skutečně nelze, protože kernel nebo proces zygote je již namapoval a změnu si nevšimne až do příštího bootu.

Úlohou VDLU je ty dvě skupiny automaticky rozlišit, aplikovat vše, co bezpečně může, **naostro**, a odložit jen skutečně boot-vázané soubory na restart, který jasně označí. Tato stránka vysvětluje jak.

Pro mechaniku enginu pod tím viz [[Engine]]. Pro velký obraz viz [[Architecture]].

## Proč prostě nerestartovat pokaždé

Restart je ta nejdražší věc, kterou aktualizace může od někoho požadovat. Přeruší, cokoli dělají, trvá minutu nebo více a cvičí lidi obávat se aktualizací. Dobrý inkrementální updater by se měl cítit neviditelně: klepnete na update, pár souborů se změní pod běžícím systémem a už jste na nové verzi.

Takže VDLU obrací obvyklý předpoklad. Výchozí je naostro. Soubor se odloží na restart jen tehdy, když je prokazatelně jedním z kernel- nebo zygote-vázaných druhů, a i pak čeká jen ten soubor. Vše kolem něj se stále aktualizuje okamžitě.

## Tři třídy

Každému souboru ve feedu je přiřazena třída. Producer ji může nastavit explicitně v manifestu, ale v praxi je třída odvozena z cesty, a engine vždy jen povýší soubor směrem k `reboot`, nikdy ho nesníží směrem k `live`. Třídy jsou:

**LIVE** je běžný případ: aktiva web UI, binární soubory, skripty čtené na vyžádání, konfigurační soubory, `module.prop` a cokoli jiného nezachyceného pravidly níže. Živý soubor se zálohuje a pak atomicky přejmenuje přes cíl, zatímco systém běží. Žádný restart a změna je v platnosti ve chvíli, kdy rename přistane.

**SOFT** jsou vlastní skripty životního cyklu modulu: `service.sh`, `post-fs-data.sh` a `boot-completed.sh`. Ty se aplikují naostro přesně jako soubory LIVE, takže nová kopie je už na disku. Důvod, proč dostávají vlastní třídu, je, že běžící systém již starou kopii tento boot provedl; nová prostě běží příští boot, bez inscenace a bez banneru. Není co odkládat, jen přirozené předání.

**REBOOT-hard** je malá sada, která se nemůže změnit pod běžícím systémem:

- nativní knihovny, `*.so` (cokoli pod cestou `zygisk/`), protože zygote je při startu mapuje do každé aplikace;
- soubory overlaye `/system`, protože overlay se mountuje při bootu;
- soubory `sepolicy.rule`, protože SELinux politika se načítá brzy.

Soubor REBOOT-hard se nikdy nezapíše přes svůj živý inode, zatímco systém běží. Přepsání `.so`, které zygote již namapoval, je způsob, jak získat pády a nekonzistentní stav. Místo toho se nový obsah **inscenuje** vedle adresáře stavu a vymění při příštím bootu, dříve než ho cokoli může namapovat.

## Cesta k třídě, na první pohled

Engine odvozuje třídu z cesty takto:

| Vzor cesty | Třída | Aplikováno |
|---|---|---|
| `zygisk/**`, `**/zygisk/**` (soubory `.so`) | REBOOT-hard | inscenováno, vyměněno pre-zygote při bootu |
| `system/**` (overlay) | REBOOT-hard | inscenováno, vyměněno při bootu |
| `*.rule` (sepolicy) | REBOOT-hard | inscenováno, vyměněno při bootu |
| `service.sh`, `post-fs-data.sh`, `boot-completed.sh` | SOFT | zapsáno naostro, běží příští boot |
| `webroot/**`, `bin/**`, `lib/**`, konfigy, `module.prop`, vše ostatní | LIVE | zapsáno naostro, účinné okamžitě |

Manifest může nést explicitní `class` na soubor, ale odvozená třída působí jako spodní hranice: pokud soubor vypadá REBOOT-hard podle své cesty, je považován za REBOOT-hard, i když manifest říká jinak. To udržuje špatně označený feed od toho, aby se kdy pokoušel za horka vyměnit `.so`.

## Jak běh zpracuje obě skupiny najednou

Během normálního `run` (cyklus DIFF na FETCH na APPLY na COMMIT popsaný v [[Engine]]) se obě skupiny zpracovávají ve stejné transakci:

```
run:
  LIVE + SOFT  --> backup -> write .vdlu-tmp -> verify -> atomic rename   (effective now)
  REBOOT-hard  --> materialize into staged/<path>.vdlu-new                (live inode untouched)

  re-hash every LIVE + SOFT file
       |
       +-- nothing staged  --> DONE
       +-- something staged --> PENDING_REBOOT  (reboot banner in the WebUI)
```

Takže po běhu, který se dotkl `.so`, už jste na nové verzi pro každý živý soubor a čeká jen inscenované části. Žurnál hlásí `reboot_pending` a WebUI zobrazuje trvalý banner zvoucí k restartu pro aktivaci inscenovaných souborů. Není žádné falešné "done": běh s inscenovanými soubory skončí v `PENDING_REBOOT`, ne `DONE`.

## Výměna při bootu

Inscenované soubory aplikuje příkaz `boot`, který hostitelský modul zapojuje do `post-fs-data.sh`, takže běží synchronně a **pre-zygote**, dříve než jakýkoli proces může namapovat nové `.so`.

`boot` provede `resume` (pro dokončení jakékoli přerušené fáze) a pak výměnu. Pro každý inscenovaný soubor REBOOT-hard:

1. potvrdí, že inscenovaná cesta zůstává uvnitř adresáře modulu (kontrola zadržení);
2. znovu zahashuje `staged/<path>.vdlu-new` proti hashi z manifestu;
3. zálohuje aktuální živý soubor;
4. `mv -f` inscenovaný soubor přes živý a `chmod`-ne ho;
5. znovu zahashuje soubor nyní na místě, pro potvrzení, že výměna přistala správně;
6. označí ho jako aplikovaný.

Až jakmile je každý inscenovaný soubor vyměněn a znovu ověřen, transakce se uzavře z `PENDING_REBOOT` na `DONE`. Pokud jakýkoli krok selže, žurnál zaznamená chybu a modul si ponechá své předchozí soubory; nic nezůstane napůl vyměněno.

Protože výměna je sekvence opětovných zahashování a atomických přejmenování, spuštění `boot` je bezpečné, i když bylo minule přerušeno. Prostě znovu zvedne inscenované soubory.

## auto_on_reboot

Inscenace je jen polovina pocitu bez restartu; druhá polovina je, že by si uživatel nikdy neměl pamatovat spustit výměnu. S `auto_on_reboot=1` v konfiguraci `post-fs-data.sh` hostitelského modulu volá `update.sh boot` při každém bootu. To znamená:

- pokud transakce čeká na restart, inscenované soubory se automaticky vymění dříve, než zygote nastartuje, a uživatel se prostě ocitne plně na nové verzi;
- pokud nic nečeká, `boot` může spustit čerstvý cyklus a aplikovat vše, včetně `.so`, v tomto jediném bootu, protože už běží pre-zygote.

Jinými slovy, inscenované `.so` nestojí uživatele nic nad rámec restartu, který stejně chystal udělat. Nemusí podruhé na nic klepat.

## Offline při bootu, bez vybíjení baterie

Někdy `boot` chce zkontrolovat feed, ale zařízení ještě nemá síť. VDLU na ni může čekat, trpělivě a levně, řízeno `boot_retry_minutes` (0 to vypne). Čekání je záměrně šetrné k baterii:

- mezi pokusy prostě `sleep`-ne, což zamrzne v hlubokém spánku, takže zařízení spí normálně a opakovaný pokus se obnoví až jakmile je zařízení stejně vzhůru;
- nedrží žádný wakelock a nedrží zámek enginu, zatímco čeká, takže ruční běh nikdy není blokován;
- před každým pokusem kontroluje, zda je síť povolena, vyhledáním kernel route, které neposílá žádný paket a nebudí radio;
- nikdy neopakuje deterministické selhání, jako špatný podpis nebo zablokovaný downgrade, jen skutečný stav nepřítomné sítě.

Samotná kontrola manifestu zůstává zdarma na jakékoli síti, takže se vždy dozvíte, že aktualizace existuje; jen stažení čeká na splnění síťové politiky, odkládajíc se čistě místo chybování.

## Viz také

- [[Engine]]: transakce, logika apply-podle-třídy a příkaz `boot` v plné délce.
- [[Architecture]]: kde engine sedí mezi producerem a WebUI.
