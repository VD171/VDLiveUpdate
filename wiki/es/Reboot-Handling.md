# Reboot Handling

Todo el objetivo de VDLU es actualizar un módulo sin reflashearlo, y, siempre que sea posible, sin reiniciar en absoluto. La mayoría de los archivos en un módulo se pueden reemplazar mientras el dispositivo está corriendo. Unos pocos genuinamente no, porque el kernel o el proceso zygote ya los ha mapeado y no notará un cambio hasta el siguiente arranque.

El trabajo de VDLU es distinguir esos dos grupos automáticamente, aplicar todo lo que puede con seguridad **en vivo**, y diferir solo los archivos genuinamente ligados al arranque a un reinicio que señala claramente. Esta página explica cómo.

Para la mecánica del motor por debajo de esto, ver [[Engine]]. Para el panorama general, ver [[Architecture]].

## Por qué no simplemente reiniciar cada vez

Un reinicio es lo más costoso que una actualización puede pedirle a alguien. Interrumpe lo que sea que estén haciendo, toma un minuto o más, y entrena a la gente a temer las actualizaciones. Un buen actualizador incremental debería sentirse invisible: tocas actualizar, unos pocos archivos cambian bajo el sistema en ejecución, y ya estás en la nueva versión.

Así que VDLU invierte el supuesto habitual. El valor por defecto es en vivo. Un archivo se difiere a un reinicio solo cuando es demostrablemente uno de los tipos ligados al kernel o al zygote, e incluso entonces solo ese archivo espera. Todo lo que lo rodea aún se actualiza de inmediato.

## Las tres clases

A cada archivo en el feed se le asigna una clase. El productor puede establecerla explícitamente en el manifiesto, pero en la práctica la clase se deriva de la ruta, y el motor solo elevará un archivo hacia `reboot`, nunca lo rebajará hacia `live`. Las clases son:

**LIVE** es el caso común: assets de la web UI, binarios, scripts que se leen bajo demanda, archivos de config, `module.prop`, y cualquier otra cosa no coincidente con las reglas de abajo. Un archivo live se respalda y luego se renombra atómicamente sobre el destino mientras el sistema corre. Sin reinicio, y el cambio está en efecto en el momento en que el rename aterriza.

**SOFT** son los propios scripts de ciclo de vida del módulo: `service.sh`, `post-fs-data.sh` y `boot-completed.sh`. Estos se aplican en vivo exactamente como los archivos LIVE, de modo que la nueva copia ya está en disco. La razón por la que reciben su propia clase es que el sistema en ejecución ya ejecutó la copia vieja en este arranque; la nueva simplemente corre en el siguiente arranque, sin etapas y sin banner. No hay nada que diferir, solo un traspaso natural.

**REBOOT-hard** es el pequeño conjunto que no puede cambiar bajo un sistema en ejecución:

- librerías nativas, `*.so` (cualquier cosa bajo una ruta `zygisk/`), porque zygote las mapea en cada app al inicio;
- archivos de overlay de `/system`, porque el overlay se monta en el arranque;
- archivos `sepolicy.rule`, porque la política SELinux se carga temprano.

Un archivo REBOOT-hard nunca se escribe sobre su inode en vivo mientras el sistema está arriba. Sobrescribir un `.so` que zygote ya ha mapeado es cómo se obtienen caídas y estado inconsistente. En cambio, el nuevo contenido se **prepara por etapas** junto al directorio de estado y se intercambia en el siguiente arranque, antes de que nada pueda mapearlo.

## De ruta a clase, de un vistazo

El motor deriva la clase de la ruta así:

| Patrón de ruta | Clase | Aplicado |
|---|---|---|
| `zygisk/**`, `**/zygisk/**` (los archivos `.so`) | REBOOT-hard | por etapas, intercambiado pre-zygote en el arranque |
| `system/**` (overlay) | REBOOT-hard | por etapas, intercambiado en el arranque |
| `*.rule` (sepolicy) | REBOOT-hard | por etapas, intercambiado en el arranque |
| `service.sh`, `post-fs-data.sh`, `boot-completed.sh` | SOFT | escrito en vivo, corre en el siguiente arranque |
| `webroot/**`, `bin/**`, `lib/**`, configs, `module.prop`, todo lo demás | LIVE | escrito en vivo, efectivo de inmediato |

El manifiesto puede llevar una `class` explícita por archivo, pero la clase derivada actúa como un piso: si un archivo luce REBOOT-hard por su ruta, se trata como REBOOT-hard aun si el manifiesto dice lo contrario. Esto evita que un feed mal etiquetado alguna vez intente hacer un hot-swap de un `.so`.

## Cómo una ejecución maneja ambos grupos a la vez

Durante un `run` normal (el ciclo DIFF a FETCH a APPLY a COMMIT descrito en [[Engine]]), los dos grupos se manejan en la misma transacción:

```
run:
  LIVE + SOFT  --> backup -> write .vdlu-tmp -> verify -> atomic rename   (effective now)
  REBOOT-hard  --> materialize into staged/<path>.vdlu-new                (live inode untouched)

  re-hash every LIVE + SOFT file
       |
       +-- nothing staged  --> DONE
       +-- something staged --> PENDING_REBOOT  (reboot banner in the WebUI)
```

Así que después de una ejecución que tocó un `.so`, ya estás en la nueva versión para cada archivo en vivo, y solo las piezas por etapas están esperando. El diario reporta `reboot_pending`, y la WebUI muestra un banner persistente invitando a un reinicio para activar los archivos por etapas. No hay un "done" falso: una ejecución con archivos por etapas termina en `PENDING_REBOOT`, no en `DONE`.

## El intercambio en el arranque

Los archivos por etapas se aplican mediante el comando `boot`, que el módulo anfitrión conecta a `post-fs-data.sh` para que corra de forma síncrona y **pre-zygote**, antes de que ningún proceso pueda mapear el nuevo `.so`.

`boot` hace un `resume` (para terminar cualquier fase interrumpida) y luego el intercambio. Por cada archivo REBOOT-hard por etapas:

1. confirma que la ruta por etapas se queda dentro del directorio del módulo (una comprobación de contención);
2. vuelve a hashear `staged/<path>.vdlu-new` contra el hash del manifiesto;
3. respalda el archivo en vivo actual;
4. hace `mv -f` del archivo por etapas sobre el en vivo y le hace `chmod`;
5. vuelve a hashear el archivo ahora en su sitio, para confirmar que el intercambio aterrizó correctamente;
6. lo marca como aplicado.

Solo una vez que cada archivo por etapas ha sido intercambiado y reverificado, la transacción se cierra de `PENDING_REBOOT` a `DONE`. Si algún paso falla, el diario registra el error y el módulo conserva sus archivos previos; nada queda intercambiado a medias.

Como el intercambio es una secuencia de re-hashes y renames atómicos, ejecutar `boot` es seguro incluso si fue interrumpido la vez anterior. Simplemente retoma los archivos por etapas.

## auto_on_reboot

Las etapas son solo la mitad de una sensación sin reinicio; la otra mitad es que el usuario nunca debería tener que recordar ejecutar el intercambio. Con `auto_on_reboot=1` en la config, el `post-fs-data.sh` del módulo anfitrión llama a `update.sh boot` en cada arranque. Eso significa:

- si una transacción está pendiente de reinicio, los archivos por etapas se intercambian automáticamente antes de que zygote inicie, y el usuario simplemente se encuentra plenamente en la nueva versión;
- si no hay nada pendiente, `boot` puede ejecutar un ciclo nuevo y aplicar todo, incluido un `.so`, en ese único arranque, dado que ya está corriendo pre-zygote.

En otras palabras, un `.so` por etapas no le cuesta al usuario nada más allá de un reinicio que iba a hacer de todos modos. No tiene que tocar nada la segunda vez.

## Sin conexión en el arranque, sin drenar la batería

A veces `boot` quiere comprobar el feed pero el dispositivo aún no tiene red. VDLU puede esperarla, con paciencia y de forma barata, controlado por `boot_retry_minutes` (0 lo desactiva). La espera es deliberadamente segura para la batería:

- entre intentos simplemente hace `sleep`, que se congela en sueño profundo, de modo que el dispositivo duerme normalmente y el reintento se reanuda solo una vez que el dispositivo ya está despierto;
- no mantiene ningún wakelock y no mantiene el lock del motor mientras espera, de modo que una ejecución manual nunca queda bloqueada;
- antes de cada intento comprueba si la red está permitida con una búsqueda de ruta del kernel que no envía ningún paquete y no despierta la radio;
- nunca reintenta un fallo determinista como una firma mala o un downgrade bloqueado, solo una condición genuina de ausencia de red.

La comprobación del manifiesto en sí se mantiene gratis en cualquier red, de modo que siempre te enteras de que existe una actualización; solo la descarga espera a que la política de red se satisfaga, difiriendo limpiamente en vez de dar error.

## Ver también

- [[Engine]]: la transacción, la lógica de apply-por-clase y el comando `boot` en su totalidad.
- [[Architecture]]: dónde se ubica el motor entre el productor y la WebUI.
