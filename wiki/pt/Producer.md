# Producer

O **producer** é o lado do PC / release do VDLU: o pequeno conjunto de ferramentas que transformam uma árvore de módulo finalizada em um feed assinado e endereçado por conteúdo do qual o dispositivo pode atualizar. Nada aqui roda no telefone. Essas ferramentas rodam na sua máquina de release (ou, para as partes que são seguras, em CI).

São quatro delas:

| Ferramenta | Roda em | Linguagem | Função |
|---|---|---|---|
| `vdlu-pack` | PC / CI | python3 | Percorre a árvore final do módulo gerando `manifest.json` + `blobs/<sha256>` |
| `vdlu-keygen` | PC | sh + openssl | Gera um par de chaves de assinatura ed25519 |
| `vdlu-sign` | PC | sh + openssl | Injeta `key_id` + assinatura em um manifesto, no lugar |
| `vdlu-gc` | PC | python3 | Poda blobs órfãos de um feed publicado (fail-safe) |

O fluxo de release tem três passos, feitos uma vez por release: **pack, depois sign, depois publish**. `vdlu-keygen` é uma configuração única, e `vdlu-gc` é limpeza que você roda quando o feed cresce. Tudo que o producer emite está em conformidade com o [[Feed Format]], que é o que o motor no dispositivo consome.

---

## vdlu-pack

`vdlu-pack` pega a **árvore exata que o seu `.zip` entrega** (a árvore final, depois que o seu build aplicou sua própria whitelist e poda de ABI) e produz o feed para ela.

```sh
vdlu-pack <module_tree_dir> <out_dir> <module_id> <version> \
          [--version-name v106] [--channel stable] [--prev ./prev/manifest.json]
```

Ele grava duas coisas em `<out_dir>`:

- `manifest.json` - a descrição completa da árvore alvo (todo arquivo com seu `sha256`, `size`, `mode`, encoding e classe de reboot), ainda **não assinado** (os campos `key_id` e `sig` são placeholders vazios).
- `blobs/<sha256>` (ou `blobs/<sha256>.gz`) - um blob por conteúdo de arquivo distinto.

### Endereçado por conteúdo e deduplicante

Todo blob é nomeado pelo **sha256 do seu conteúdo original (descomprimido)**. Como o nome é o hash, conteúdo idêntico aterrissa no mesmo blob. `vdlu-pack` grava um blob apenas se ele ainda não está presente, então:

- Um arquivo que não mudou mantém o mesmo nome de blob, e nunca é reescrito ou reenviado.
- Dois arquivos diferentes com conteúdo idêntico compartilham um blob.
- Um arquivo revertido reusa o blob que já estava lá de antes.

A publicação é, portanto, **incremental por construção**: entre releases, `blobs/` só cresce, e apenas conteúdo genuinamente novo é adicionado. O dispositivo busca pelos mesmos hashes, então baixa apenas os blobs que ainda não possui.

### Compressão (o campo `enc`)

Para cada arquivo, `vdlu-pack` decide como armazenar o blob:

- `gz` quando o arquivo tem ao menos 4096 bytes **e** o gzip (determinístico `-9 -n`) economiza ao menos 10 por cento.
- `raw` caso contrário (arquivos pequenos que o gzip on-the-wire já cobre, ou dados já incompressíveis).
- Se o `gzip` está faltando no host de build, tudo é armazenado `raw`. O packing nunca falha por isso.

O `sha256` no manifesto é **sempre** do conteúdo original; `enc` apenas nomeia como o blob acaba sendo armazenado. O dispositivo descomprime blobs `gz` com o `gunzip` do toybox e então confere o hash contra o original.

### Classe de reboot e segurança

`vdlu-pack` também marca cada arquivo com uma `class` de reboot (`live`, `soft`, `reboot`) derivada do seu caminho, para que o motor saiba o que pode ser aplicado sem um reinício e o que deve ser estagiado. As regras e o que o dispositivo faz com cada classe são cobertas em [[Reboot Handling]].

Algumas coisas que `vdlu-pack` deliberadamente **não** faz:

- Ele não segue symlinks (ele os pula com um aviso, de modo que conteúdo de fora da árvore, como um link para um arquivo de sistema, nunca pode vazar para um blob).
- Ele pula arquivos não regulares (diretórios, fifos, devices).
- Ele respeita `SOURCE_DATE_EPOCH` para o timestamp `built`, então os manifestos são reproduzíveis.
- Ele exclui um conjunto fixo de caminhos do feed inteiramente (a raiz de confiança, o scaffolding do instalador e alguns outros). A lista completa, e por que cada um é excluído, está em [[Feed Format]].

### A lista `delete[]`

Passe `--prev <previous manifest.json>` e `vdlu-pack` computa `delete[]`: os caminhos que existiam no release anterior mas sumiram neste, de modo que o dispositivo os remove em vez de deixar órfãos para trás. Caminhos excluídos nunca são emitidos como deletes, mesmo quando aparecem no manifesto anterior (veja [[Feed Format]] para a semântica exata).

---

## vdlu-keygen

Um passo único. `vdlu-keygen` cria o par de chaves de assinatura ed25519 para o seu feed.

```sh
vdlu-keygen <id> <out_dir>
```

Ele grava três arquivos:

| Arquivo | O que é | Para onde vai |
|---|---|---|
| `<id>.pem` | A chave de assinatura **privada** (mode `0600`) | Fica na sua máquina de release. Nunca. |
| `<id>.pub` | A chave pública como PEM | Apenas para tooling do lado do PC |
| `<id>.pub.raw` | A chave pública como **32 bytes brutos** | Enviada como a entrada de keyring do módulo no dispositivo |

A chave pública bruta de 32 bytes é o que o verificador do dispositivo lê (ele não carrega `openssl`, então não consegue ler o PEM). Você embarca `<id>.pub.raw` no módulo como `vdlu/keyring/<id>.pub`. O PEM é só para uso do lado do PC. Essa divisão, e como a rotação de chaves funciona, é explicada em [[Security and Trust Model]].

> A `.pem` privada é o único segredo em todo o sistema. Mantenha-a fora de todo dispositivo e de todo push de repositório. Veja a nota de CI abaixo.

---

## vdlu-sign

`vdlu-sign` pega o manifesto não assinado que o `vdlu-pack` produziu e o assina **no lugar**.

```sh
vdlu-sign <manifest.json> <privkey.pem> <key_id>
```

Ele define o campo `key_id`, computa a forma canônica do manifesto e grava a assinatura ed25519 (base64) no campo `sig`. A assinatura é sobre uma transformação de bytes precisa do manifesto, de modo que o PC e o dispositivo derivam exatamente os mesmos bytes assinados sem nenhuma biblioteca JSON no dispositivo. Essa transformação (a **canonicalização**) é o invariante mais importante do formato, e está documentada por completo em [[Feed Format]].

A chave privada é lida apenas aqui, na sua máquina, e nunca a deixa.

### A chave de assinatura fica fora do CI

Este é um ponto de design deliberado. O CI pode rodar `vdlu-pack` e produzir uma **baseline sem chave** perfeitamente válida (um manifesto de seed não assinado; veja [[Feed Format]]), de modo que uma instalação nova nasce atual sem o CI nunca tocar uma chave privada. A assinatura de fato do feed publicado é feita por você, localmente, com `vdlu-sign`. Desse jeito a chave de assinatura fica 100 por cento fora do CI, e apenas o feed que você publica à mão é assinado.

---

## vdlu-gc

Como os blobs são endereçados por conteúdo e imutáveis, `blobs/` só cresce: `vdlu-pack` adiciona, nunca remove. Ao longo de muitos releases o feed (e o site Pages que o hospeda) acumula blobs que nenhum manifesto atual referencia mais. `vdlu-gc` poda esses órfãos.

```sh
vdlu-gc <feed_dir> [--keep-last N] [--keep extra.json ...] [--apply]
```

Ele constrói o **conjunto retido** de manifestos: o `manifest.json` atual, mais os últimos `N` manifestos arquivados por versão (padrão `N=3`, dando uma margem de rollback), mais quaisquer que você nomeie com `--keep`. Um blob referenciado por **nenhum** manifesto retido é um órfão e é candidato a remoção. O conjunto retido é uma união, então um blob fica enquanto qualquer release retido ainda precisar dele; um dispositivo parado em uma versão retida mais antiga nunca perde seu fetch.

`vdlu-gc` foi construído para ser seguro:

- **Dry-run por padrão.** Sem `--apply`, ele apenas imprime o que *removeria*. Você adiciona `--apply` para deletar de verdade.
- **Fail-safe.** Se não encontra nenhum manifesto retido, ele se recusa a podar em vez de arriscar esvaziar um feed.
- **Retenção por referência, não por data.** Um blob é mantido porque um manifesto retido aponta para ele, nunca por causa de um timestamp.

Depois de podar, envie o feed menor para o seu host. Espace a escrita se o seu host limita a taxa de escritas em lote.

---

## Juntando tudo

Um release típico, de ponta a ponta:

```sh
# one-time: make a signing key. Keep the .pem off every device and every repo push.
vdlu-keygen release-2026 ./keys

# each release: pack the final shipped tree (post-whitelist, same tree the .zip ships)
vdlu-pack ./module_tree ./out demo 106 --version-name v106 --channel stable \
          --prev ./prev/manifest.json

# sign the manifest in place (local, private key never leaves your machine)
vdlu-sign ./out/manifest.json ./keys/release-2026.pem release-2026

# publish ./out/{manifest.json,blobs/} to your source (GitHub Pages, rsync, ...).
# occasionally: prune orphan blobs
vdlu-gc ./feed --keep-last 3            # dry-run first
vdlu-gc ./feed --keep-last 3 --apply    # then delete
```

Para o exemplo trabalhado completo de adotar o VDLU em um módulo, veja [[Quick Start]]. Para o formato on-wire de tudo que o producer emite, veja [[Feed Format]]. Para o raciocínio por trás do manuseio de chaves e do que é mantido fora do feed, veja [[Security and Trust Model]].
