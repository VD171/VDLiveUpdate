> **Languages:** [English](../../SECURITY.md) · [العربية](../ar/SECURITY.md) · [Čeština](../cs/SECURITY.md) · [Deutsch](../de/SECURITY.md) · Español · [فارسی](../fa/SECURITY.md) · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · [Italiano](../it/SECURITY.md) · [日本語](../ja/SECURITY.md) · [한국어](../ko/SECURITY.md) · [Nederlands](../nl/SECURITY.md) · [Polski](../pl/SECURITY.md) · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · [中文](../zh/SECURITY.md)

---

# Política de seguridad

VDLiveUpdate (VDLU) aplica actualizaciones flashless con root a un módulo en vivo:
escribe en el propio directorio del módulo e intercambia una `.so` Zygisk en el arranque,
ejecutándose en el contexto root del módulo. Nos tomamos la seguridad en serio.

## Reportar una vulnerabilidad

- **Site:** https://vd171.ru
- **Site:** https://vd.priv8.ru
- **Issues:** https://github.com/VD171/VDLiveUpdate/issues
- **GitHub:** [@VD171](https://github.com/VD171)
- **XDA-Developers:** [@VD171](https://xdaforums.com/m/vd171.4699873/)
- **Telegram:** [@VD_Priv8](https://t.me/VD_Priv8)
- **Channel:** [@Priv8_VD](https://t.me/Priv8_VD)
- **Discord:** [@VD.Priv8](https://discord.com/users/1296831918989639721)
- **E-mail:** vd.priv8@pm.me

Incluye una descripción clara y, si es posible, un manifiesto o feed que reproduzca el
problema. Responderemos tan pronto como podamos y te daremos crédito si lo deseas.

## Notas de alcance

- Las actualizaciones son blobs content-addressed más un `manifest.json` firmado con
  ed25519. El dispositivo verifica la firma con un `ed25519-mini` incorporado (sin openssl
  en el dispositivo), y cada blob se comprueba contra su `sha256` antes de usarse.
- El perfil hardened (el valor predeterminado público) exige una firma válida y bloquea el
  downgrade. La versión "de origen" tiene como piso el `versionCode` del módulo instalado
  (leído de `module.prop`), por lo que un módulo nunca se revierte por detrás del feed.
- La raíz de confianza (la clave pública ed25519 raw del `keyring/` y los binarios de
  `verify/`) es solo-flash y nunca se rota por la red. El productor la excluye del feed y
  el engine ignora toda ruta `vdlu/` en un plan descargado, por lo que una clave de firma
  filtrada no puede cambiar el verificador o la clave y persistir root.
- Un manifiesto firmado válidamente para otro módulo no puede escribir en el directorio de
  un módulo diferente. El campo `module` firmado debe ser igual al `MODID` del dispositivo
  (verificación de vínculo entre módulos), y toda escritura y borrado queda confinado al
  directorio del módulo.
- El engine se ejecuta en el propio contexto root del módulo y nunca lo debilita. No añade
  privilegios y no interpola ningún campo del manifiesto en un shell, cada valor de `path`,
  `sha256`, `mode` y `delete[]` se valida como entrada hostil antes de usarse.
- La postura es fail-closed. Un valor de `profile` corrupto o desconocido nunca cae en
  aceptar contenido sin firmar (cualquier cosa que no sea exactamente `trusted` se trata
  como `hardened`), y se escribe una copia de seguridad antes de sobrescribir cualquier
  archivo, por lo que un apply fallido nunca destruye la versión instalada.
- Consulta [TRUST-MODEL.md](TRUST-MODEL.md) para el modelo de confianza completo, las
  garantías fail-closed y los detalles de hardening.

<!-- doc-footer -->

---

> _Esta documentación se generó con Claude (Anthropic) y la mantiene VD171. Las correcciones y mejoras son bienvenidas, consulta [CONTRIBUTING.md](CONTRIBUTING.md)._
