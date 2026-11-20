# Contributing

Las contribuciones son bienvenidas. VDLU es un motor de autoactualización incremental y sin flasheo
incorporado en módulos de KernelSU / APatch / Magisk. Esta página es el flujo de trabajo práctico de
desarrollo; para cómo encajan las piezas, lee primero [[Architecture]], [[Engine]] y
[[Producer]].

## Nada compila

VDLU son scripts (`sh` POSIX, un poco de Python en el lado de publicación, JS plano para la
WebUI), de modo que no hay paso de build. Verificas un cambio ejecutando la tubería
de principio a fin y comprobando estáticamente cada pieza.

## Primero el contrato de la costura

El contrato de interfaz entre los componentes (las firmas de CLI, los nombres de archivo y
las claves JSON compartidas por el motor, el productor y la WebUI) es la **ley de
convergencia**. Trátalo como inmutable. Si tu cambio toca la
costura productor-a-motor (esquema del manifiesto, esquema del diario, claves de config, la
regla de firma/canonicalización), **alinea primero el contrato de interfaz**, luego
cambia el código en ambos lados para que coincida. Un cambio en un lado de la costura sin
el otro rompe en silencio a los adoptantes. Ver [[Producer]] para la regla de canonicalización
en la que el firmador y el verificador deben concordar byte a byte.

## Probar de principio a fin antes de un PR

Ejecuta el productor y el motor juntos sobre un árbol desechable, de la misma forma que
la publicación de un adoptante lo hace:

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

Luego comprueba estáticamente cada componente:

```sh
sh -n engine/*.sh            # POSIX sh syntax, must pass
node --check webui/vdlu.js   # WebUI JS syntax
```

Y abre `webui/demo.html` en un navegador: simula el puente del gestor de root
(`ksu.exec`), de modo que puedas ejercitar el panel de Updates, el toast de progreso, la cancelación
y el banner de reinicio sin dispositivo. Ver [[WebUI]].

## Reglas de la casa

- **`sh` POSIX en el dispositivo.** Sin bashismos más allá de `local`, y sin `jq`. Tiene que
  correr en toybox / busybox.
- **La seguridad es innegociable.** Cada campo del manifiesto es entrada hostil;
  `validate_plan()` se mantiene a prueba de fallos, y la clave de firma privada nunca toca
  CI ni un dispositivo. No aflojes una comprobación para hacer pasar una prueba.
- **Rigor ante el fallo.** Mantén la transacción reanudable: nada reporta "done"
  sin un re-hash coincidente, nada se sobrescribe sin un respaldo, y los
  applies se mantienen atómicos.
- **Siempre calidad de release.** Mantén los comentarios concisos; sin comentarios gratuitos.
- **Un cambio lógico por PR.** Di qué cambió y por qué.

## Reportar issues

Abre un issue describiendo qué hiciste, qué esperabas y qué pasó.
Para un bug, incluye el id del módulo, el perfil de la fuente (`hardened` o `trusted`),
el comando `update.sh` que ejecutaste, y el `journal.json` relevante (registra la
fase, el estado y el error). Para una función, di qué componente toca (motor,
productor o WebUI) para que el impacto en la costura esté claro de entrada.
