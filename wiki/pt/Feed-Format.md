# Feed Format

O **feed** é o que o VDLU serve pela rede e de onde o dispositivo atualiza. É um diretório estático comum, servível por qualquer coisa (GitHub Pages, um alvo rsync, um caminho `file://`):

```
<source>/
  manifest.json          # the signed description of the current release
  blobs/<sha256>         # one blob per distinct file content
  blobs/<sha256>.gz      # (when the blob is stored gzipped)
```

O próprio módulo também traz um arquivo extra, `baseline.json`, dentro do `.zip` (não servido a partir do feed). O producer que constrói tudo isso está descrito em [[Producer]]; esta página é o contrato on-wire.

---

## manifest.json

O manifesto é a descrição completa de um release: todo arquivo na árvore alvo, o que deletar e a assinatura sobre a coisa inteira.

```json
{
  "schema": 1,
  "module": "demo",
  "version": 106,
  "version_name": "v106",
  "built": "2026-11-19T12:00:00Z",
  "engine_min": 3,
  "channel": "stable",
  "key_id": "release-2026",
  "files": [
    {
      "path": "webroot/index.html",
      "sha256": "<hex64>",
      "size": 1234,
      "mode": "0644",
      "enc": "raw",
      "class": "live"
    }
  ],
  "delete": ["webroot/old.html"],
  "sig": "<base64>"
}
```

### Campos

| Campo | Significado |
|---|---|
| `schema` | Versão do formato do próprio manifesto (atualmente `1`). |
| `module` | O id do módulo. O dispositivo rejeita o manifesto se ele não corresponde ao seu próprio id de módulo, de modo que um feed validamente assinado para um módulo diferente não pode ser servido em seu lugar. |
| `version` | Versão inteira. O motor atualiza apenas para frente; um feed mais antigo que o dispositivo é um estado benigno de "ahead", não um erro. |
| `version_name` | String de versão legível por humanos (por exemplo `v106`). |
| `built` | Timestamp de build ISO 8601. Respeita `SOURCE_DATE_EPOCH` para reprodutibilidade. |
| `engine_min` | A versão mínima do motor necessária para aplicar este manifesto. |
| `channel` | Canal de release (por exemplo `stable`). |
| `key_id` | Qual chave no keyring do dispositivo assinou este manifesto. Seleciona a chave pública para verificação, e deve estar na lista de permissão de atualização de módulo do motor (veja [[Security and Trust Model]]); uma chave meramente presente no keyring mas não na lista de permissão é rejeitada antes de sua pubkey ser carregada. |
| `files[]` | A árvore alvo **completa** (não um diff). Cada entrada: `path`, `sha256`, `size`, `mode`, `enc` (`raw`/`gz`), `class` (`live`/`soft`/`reboot`). |
| `delete[]` | Caminhos presentes no release anterior mas sumidos agora, para o dispositivo remover. |
| `sig` | A assinatura ed25519, base64. Veja a canonicalização abaixo. |

`files[]` descreve a árvore **inteira**, não um delta. O dispositivo computa o delta por conta própria comparando o manifesto contra o que já tem, e busca apenas os blobs cujo `sha256` está faltando. O `sha256` é sempre do conteúdo original (descomprimido); `enc` apenas diz como aquele blob é armazenado em `blobs/`. O significado de `class` e o que o dispositivo faz com cada valor é coberto em [[Reboot Handling]].

---

## Canonicalização (os bytes assinados)

Este é o invariante mais importante do formato. O assinador do PC e o verificador no dispositivo rodam em runtimes completamente diferentes (openssl no PC, toybox + um verificador minúsculo embarcado no dispositivo, e **nenhuma biblioteca JSON** no dispositivo). Eles ainda assim devem derivar exatamente os mesmos bytes para assinar e para verificar. A regra é, portanto, uma **transformação de bytes** deliberada, não uma re-serialização de JSON.

**Passo 1: uma forma de armazenamento fixa.** `vdlu-pack` grava `manifest.json` compacto, com chaves ordenadas, UTF-8, sempre incluindo `key_id` e `sig` (como strings vazias até ser assinado):

```
json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
```

**Passo 2: remover apenas `sig`.** A forma canônica é aquele texto exato com **apenas o campo `"sig"` removido**. Como as chaves são ordenadas, `sig` sempre aparece como `,"sig":"<value>",` cercado por `"schema"` antes dele e `"version"` depois (ambos sempre presentes), então removê-lo deixa texto bem formado. O JSON escapa toda `"` dentro de um valor de string como `\"`, então o token estrutural `"sig":"` é inequívoco mesmo contra um nome de arquivo que literalmente contenha `"sig":"`.

A remoção é um punhado de expansões de parâmetro POSIX, idênticas no assinador e no verificador, sem `sed` e sem `jq`:

```sh
# $1 = the full manifest text
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

**Passo 3: assinar o hash disso.** A mensagem assinada/verificada é o **sha256 hex** (64 caracteres ASCII, sem newline) da forma canônica. O ed25519 assina esse hex.

Duas consequências caem disso por construção:

- `key_id` faz parte da forma canônica (apenas `sig` é removido). `vdlu-sign` define `key_id` **antes** de fazer o hash, então a identidade da chave é coberta pela assinatura.
- Quer o placeholder `sig` esteja vazio (`"sig":""`, no momento da assinatura) ou preenchido (no momento da verificação), removê-lo produz os bytes canônicos idênticos. Assinar e verificar concordam automaticamente.

As duas ferramentas sh POSIX são autoritativas. Um equivalente em Python, `re.sub(r'"sig":"[^"]*",', '', text, count=1)` seguido de sha256, existe apenas para checá-las de forma cruzada.

O raciocínio de confiança em torno de tudo isso (por que a verificação é no dispositivo, como o `hardened` falha closed) vive em [[Security and Trust Model]].

---

## baseline.json (o seed de instalação)

Quando um módulo é recém instalado, ele deve já estar "atual" para sua própria versão enviada, sem nenhuma autoatualização desnecessária da versão que acabou de instalar. É isso que o `baseline.json` faz.

`baseline.json` vem **dentro do zip do módulo** (em `vdlu/baseline.json`), não no feed. Em uma instalação nova, o motor semeia seu registro de "versão ativa" a partir dele, de modo que o dispositivo nasce atual, sem `from:0` e sem re-fetch do que ele já tem.

Propriedades-chave:

- É uma **cópia sem chave do manifesto assinado** para a versão enviada: a mesma saída do `vdlu-pack`, deixada não assinada (`key_id` e `sig` ficam vazios).
- Ele **não é verificado**. O motor o trata como um seed local confiável porque ele chegou dentro do zip flashado, que é a fronteira de confiança da instalação. Apenas um manifesto *buscado do feed* passa por verificação de assinatura.
- Como ele não precisa de assinatura, **o CI pode gerá-lo sem chave**, o que é o que mantém a chave de assinatura inteiramente fora do CI (veja [[Producer]]).
- `vdlu-pack` **exclui `baseline.json` do seu próprio manifesto**, de modo que o manifesto nunca referencia a baseline (isso seria um loop de auto-referência: manifesto para baseline para manifesto).
- É **não fatal se ausente**. Sem ele, o dispositivo simplesmente parte de `from:0` em sua primeira atualização e busca o que precisa. Nunca quebrado, apenas menos ótimo.

---

## Blobs

Cada conteúdo de arquivo distinto é um blob sob `blobs/`, nomeado pelo **sha256 do conteúdo original**:

- `blobs/<sha256>` para um blob raw.
- `blobs/<sha256>.gz` para um blob gzipado (o gzip é mantido apenas quando o arquivo tem ao menos 4096 bytes e a compressão economiza ao menos 10 por cento).

Um blob é armazenado uma vez, em um formato. O endereçamento por conteúdo dá a deduplicação de graça: conteúdo inalterado, compartilhado ou revertido mapeia para um blob que já existe, então o feed cresce apenas por conteúdo genuinamente novo, e o dispositivo baixa apenas os hashes que está faltando. O dispositivo confere o `sha256` de todo blob baixado contra o manifesto (depois de descomprimir um blob `gz`) antes de usá-lo.

---

## O que é excluído do feed, e por que

O feed carrega **apenas o conteúdo próprio do módulo**. Um conjunto fixo de caminhos é mantido fora dele de propósito. `vdlu-pack` aplica um predicado de exclusão tanto ao percorrer a árvore quanto ao computar `delete[]`.

| Excluído | Por que |
|---|---|
| `vdlu/keyring/`, `vdlu/verify/` (a raiz de confiança: chaves públicas brutas + o binário verificador) | **Esta é a razão de segurança central.** O âncora de confiança é **flash-only**. Se o keyring ou o verificador fossem entregáveis por feed, um manifesto poderia sobrescrever exatamente a coisa que o valida. Mantê-los fora do fio significa que um manifesto nunca pode reescrever o âncora de confiança no dispositivo. |
| `vdlu/baseline.json` | É uma cópia do manifesto assinado (o seed de instalação); empacotá-lo seria um loop de auto-referência. |
| `.vd/` infraestrutura de flash | Scaffolding de flash-gate que vem no zip, nunca aplicado ao vivo. |
| `update.json`, `update-mmrl.json` | Seu size/sha são preenchidos pelo CI *depois* que os zips são construídos, então a cópia enviada difere de qualquer cópia de feed. Alimentá-los causaria um fetch fantasma de arquivo único na primeira autoatualização de toda instalação, e eles são vestigiais no dispositivo de qualquer forma (o manager lê o JSON de update remoto bruto). |
| `META-INF/`, `customize.sh` (scaffolding do instalador) | Consumidos pelo manager no momento do **flash** e não mantidos no módulo instalado. Eles não são conteúdo do VDLU; servi-los desperdiça blobs e, se um algum dia mudasse entre versões, ele seria gravado como um arquivo de instalador no diretório do módulo ao vivo. |
| Companheiros `.sha256` por arquivo | Eles pertencem apenas ao zip flashável, ficam obsoletos depois de uma atualização incremental e dobrariam o manifesto. |
| Arquivos de dev/doc (`RELEASE.md`, `CLAUDE.md`, `.gitignore`) | Nunca enviados ao dispositivo; servi-los desperdiça blobs e agita o manifesto assinado a cada edição de doc. |

O raciocínio por trás da exclusão da raiz de confiança é expandido em [[Security and Trust Model]].

---

## Semântica de delete[]

`delete[]` diz ao dispositivo quais caminhos remover, de modo que um arquivo descartado entre releases não fique no dispositivo como um órfão. Ele é computado passando `--prev <previous manifest.json>` ao `vdlu-pack`: um caminho que estava no release anterior e não está no atual vira uma entrada de delete.

A regra importante: **caminhos excluídos nunca são emitidos como deletes, mesmo com `--prev`.** Todo caminho anterior é passado pelo mesmo predicado de exclusão usado ao percorrer a árvore. Se um `--prev` aponta para um manifesto mais antigo que ainda listava caminhos agora excluídos (um `baseline.json` perdido, `META-INF/*`, uma entrada de keyring, e assim por diante), esses caminhos **não** são transformados em entradas de delete. Um caminho excluído nunca foi conteúdo de feed, então não é do VDLU para deletar, e o dispositivo nunca é ordenado a remover um arquivo que não foi servido pelo feed. É isso que impede a lista de exclusão de algum dia voltar como uma instrução destrutiva.
