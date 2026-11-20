> **Languages:** [English](../PRODUCER.md) · [العربية](../ar/PRODUCER.md) · [Čeština](../cs/PRODUCER.md) · [Deutsch](../de/PRODUCER.md) · [Español](../es/PRODUCER.md) · [فارسی](../fa/PRODUCER.md) · [Français](../fr/PRODUCER.md) · [हिन्दी](../hi/PRODUCER.md) · [Bahasa Indonesia](../id/PRODUCER.md) · [Italiano](../it/PRODUCER.md) · [日本語](../ja/PRODUCER.md) · [한국어](../ko/PRODUCER.md) · [Nederlands](../nl/PRODUCER.md) · [Polski](../pl/PRODUCER.md) · Português · [Русский](../ru/PRODUCER.md) · [Svenska](../sv/PRODUCER.md) · [ไทย](../th/PRODUCER.md) · [Türkçe](../tr/PRODUCER.md) · [Українська](../uk/PRODUCER.md) · [Tiếng Việt](../vi/PRODUCER.md) · [中文](../zh/PRODUCER.md)

---

# Camada de producer + assinatura do VDLU

Constrói a entrega endereçada por conteúdo (manifesto + blobs) de um módulo e a assina.
Conforma-se a [`INTERFACES.md`](INTERFACES.md) §3/§6/§7.

| ferramenta | roda em | linguagem | tarefa |
|---|---|---|---|
| `producer/vdlu-pack` | PC / CI | python3 | percorre a árvore final do módulo -> `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | PC | sh + openssl | par de chaves ed25519 (`<id>.pem` priv, `<id>.pub` PEM, `<id>.pub.raw` RAW 32B para o keyring enxuto) |
| `producer/vdlu-sign` | PC | sh + openssl | injeta `key_id` + `sig` num manifesto, in place |
| `engine/vdlu-verify` | **device** | sh + ed25519-mini | verifica `sig` via o ed25519-mini embarcado; keyring = pubkey RAW 32B (SEM openssl no device) |

## Pipeline

```sh
# 1. one-time: a signing key. Keep the .pem off every device and off any repo push.
producer/vdlu-keygen release-2026 ./keys

# 2. each release: pack the final tree (same tree the .zip ships, post-whitelist).
producer/vdlu-pack  ./module_tree  ./out  demo 106 --version-name v106 --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev

# 3. sign the manifest in place.
producer/vdlu-sign  ./out/manifest.json  ./keys/release-2026.pem  release-2026

# 4. publish ./out/{manifest.json,blobs/} to <source> (Pages batch for public; rsync for private).
#    The slim device keyring holds ./keys/release-2026.pub.raw as keyring/release-2026.pub (RAW 32B).
```

O `vdlu-pack` é endereçado por conteúdo e deduplicante: um blob cujo `<sha256>` já existe não é
reescrito, então a publicação é incremental e o conteúdo inalterado / revertido nunca é re-enviado.

### Decisão de `enc` (vdlu-pack)

`sha256` é **sempre** do conteúdo original (descomprimido); `enc` só nomeia como o blob é armazenado.

- `gz` quando `size >= 4096` **e** o gzip (`-9 -n`, determinístico) economiza ao menos 10% (`comp <= raw*0.90`).
- `raw` caso contrário (texto pequeno que o gzip do HTTP já cobre, ou dado já-incompressível).
- gzip faltando no host de build -> tudo `raw` (nunca falha).

Um blob é armazenado uma vez, num formato: `blobs/<sha256>` (raw) ou `blobs/<sha256>.gz` (gz). O device
descomprime com o `gunzip` do toybox (sempre presente), então nenhum zstd é embarcado.

### Decisão de `class` (vdlu-pack) - taxonomia de reboot

Derivada do path (INTERFACES §3, doc §4). Só defaults; uma regra de path nunca rebaixa `reboot`->`live`.

| class | casada por | aplicada |
|---|---|---|
| `reboot` | `system/**`, `zygisk/**/*.so`, `*.rule` | encenada `.vdlu-new`, swap no boot |
| `soft` | `service.sh` / `post-fs-data.sh` / `boot-completed.sh` na raiz | escrita live, roda no próximo boot |
| `live` | todo o resto (webroot, bin, lib, confs, module.prop, ...) | escrita live, atômica |

Symlinks **não são seguidos** (nunca vaza conteúdo de fora da árvore, ex. um link para
`/etc/shadow`) e são pulados com um aviso, já que o schema do manifesto não tem tipo symlink.
Arquivos não-regulares (dirs, fifos, devices) são pulados. `built` honra `SOURCE_DATE_EPOCH` para
manifestos reprodutíveis.

### Baseline (a semente de instalação) - não-assinada, sem chave

`baseline.json` (entregue em `vdlu/baseline.json` no zip do módulo) semeia `current.json` numa instalação limpa
para que o device nasça "atualizado" (sem from:0, sem re-fetch). O engine o trata como uma **semente local confiável**
(chegou no zip flasheado, que é a fronteira de confiança da instalação) e **NÃO verifica sua assinatura** -
só o manifesto BUSCADO do feed passa pelo `vdlu-verify`. Então a baseline não precisa de **chave**: é
apenas a saída do `vdlu-pack` sobre a árvore entregue (não-assinada; `sig`/`key_id` ficam vazios). Um CI pode portanto
gerá-la **sem chave**, mantendo a chave de assinatura 100% fora do CI - só o FEED publicado é assinado (operador,
localmente). O `vdlu-pack` exclui `baseline.json` do seu próprio manifesto (anti auto-referência). Não-fatal se
ausente: o device só começa de from:0 na primeira atualização, nunca quebrado.

## Canonicalização (o ponto de convergência)

`vdlu-sign` e `engine/vdlu-verify` precisam derivar os **mesmos bytes** de um manifesto, em dois
runtimes diferentes (openssl no PC vs toybox no device). A regra é deliberadamente uma transformação
de bytes, não uma re-serialização de JSON, para não precisar de biblioteca JSON no device:

1. `vdlu-pack` escreve `manifest.json` **compacto, chaves ordenadas, UTF-8**
   (`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`), sempre incluindo
   os campos `key_id` e `sig` (placeholders de string vazia até ser assinado). Esta é a forma canônica
   de armazenamento.
2. **Forma canônica = aquele texto com o campo `"sig"` removido.** Como as chaves são ordenadas, `sig`
   sempre aparece como `,"sig":"<value>",` cercado por `"schema"` (antes) e `"version"` (depois),
   ambos sempre presentes. Removê-lo deixa `...,"schema":N,"version":...` bem-formado.
   JSON escapa todo `"` dentro de valores string para `\"`, então o token estrutural `"sig":"` é
   inequívoco mesmo contra um nome de arquivo que contenha literalmente `"sig":"` (testado).
3. A mensagem assinada/verificada é o **hex sha256** (64 chars ASCII, sem newline) da forma
   canônica. ed25519 sobre esse hex (`openssl pkeyutl -sign/-verify -rawin`).

A remoção em sh POSIX (função idêntica em ambas as ferramentas, sem `sed`/`jq`):

```sh
# $1 = full manifest text (trailing newline already stripped by $(cat ...))
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

`key_id` faz parte da forma canônica (só `sig` é removido); o `vdlu-sign` define `key_id` **antes** de
hashear. O placeholder do valor estando vazio (`"sig":""`, hora de assinar) ou preenchido (hora de verificar) produz os
bytes canônicos idênticos, então sign e verify concordam por construção.

Python o reproduz como `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)` e então sha256 - usado
só para conferência cruzada; os produtores autoritativos são as duas ferramentas sh.

## Assinatura (ed25519)

- `vdlu-keygen` (PC): `openssl genpkey -algorithm ed25519` (priv `0600`) + `openssl pkey -pubout` (pub **PEM**,
  para assinar/openssl) + `openssl pkey -pubout -outform DER | tail -c 32` -> **`.pub.raw` (RAW 32B)** (o DER
  SPKI ed25519 é um prefixo de 12 bytes + a chave de 32 bytes, então `tail -c 32` É a chave). Emite AMBOS.
- `vdlu-sign` (PC): `openssl pkeyutl -sign -rawin` sobre o hex sha256 canônico; assinatura armazenada em base64.
- `vdlu-verify` (**device, enxuto**): `ed25519-mini <pubkey32> <msg> <sig64>` - lê o keyring como a pubkey **RAW 32B**,
  SEM openssl no device. `key_id` é path-sanitizado (sem `/`, `.`, `..`, `"`). 🚨 O keyring entrega o
  **`.pub.raw` (32B)**, nunca o `.pub` PEM (113B): o PEM é só PC-side e o `ed25519-mini` não consegue lê-lo.

Modelo de confiança (INTERFACES §6, doc §11/§13): `profile=hardened` (público) torna o verify obrigatório - uma
assinatura falha ou ausente aborta a atualização. `profile=trusted` (privado, fonte staged via SSH) trata o
verify como best-effort, mas o sha256 de todo blob é conferido de qualquer forma.

## Keyring + rotação

O keyring é um diretório de arquivos `<key_id>.pub`, cada um a pubkey ed25519 **RAW 32B** (do
`.pub.raw` do `keygen`), NÃO PEM - o `ed25519-mini` lê 32 bytes crus. Entregue a pubkey crua atual **e** a
anterior (doc §13) para que uma chave rotacionada não brique instalações antigas. O `vdlu-sign` com o novo `key_id` e o device
escolhendo `<keyring>/<key_id>.pub` (cru) é todo o mecanismo de rotação - sem mudança no engine. O keyring é
**estável** entre releases (só a rotação de chave o muda): um re-vendor deve **verificar-não-copiar** e nunca
sobrescrevê-lo com o `.pub` PEM do PC.

**Keyrings multi-chave PRECISAM fixar a chave do módulo.** O engine restringe qual `key_id` pode assinar um MODULE-UPDATE à allowlist `key_id` da config (INTERFACES §5/§6), conferida fail-closed antes de a pubkey ser selecionada. Um keyring de chave única é seguro por padrão (aquela única chave é aceita). Mas um módulo cujo keyring TAMBÉM carrega uma chave de menor confiança - ex.: uma chave de fingerprint-feed ao lado da chave de release - é rejeitado até seu `config` declarar a chave do módulo, ex.: `key_id=vd-2026` (separado por vírgula para rotação, ex.: `key_id=vd-2026,vd-2027`). Isso impede que uma chave de menor confiança vazada assine uma atualização root flashless.

O `vdlu-pack` **exclui o keyring e os binários `verify/` do feed** (a raiz de confiança é só-flash, nunca servida pela rede), junto com `baseline.json`, o scaffolding do instalador (`META-INF/`, `customize.sh`), o portão de flash `.vd/`, os `update.json`/`update-mmrl.json` preenchidos pelo CI, e os companheiros `.sha256` por arquivo. Só o conteúdo do próprio módulo é atualizável pelo feed, então um manifesto nunca pode reescrever a âncora de confiança no device.

<!-- doc-footer -->

---

> _Esta documentação foi gerada com o Claude (Anthropic) e é mantida por VD171. Correções e melhorias são bem-vindas; veja [CONTRIBUTING.md](CONTRIBUTING.md)._
