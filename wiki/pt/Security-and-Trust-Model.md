# Security and Trust Model

O VDLU atualiza um módulo no lugar, pela rede, como root. Isso é muito poder apontado para um arquivo que vem de um feed, então todo o motor é construído sobre uma única premissa:

> **Todo campo no manifesto é entrada hostil.**

Um feed pode ser envenenado na origem, ou trocado e adulterado em trânsito por um MITM. Quando isso acontece o manifesto ainda chega parecendo um manifesto: ele carrega caminhos de arquivo, strings `sha256`, uma lista `delete[]`, modes, classes e uma flag de encoding. O VDLU não trata nenhum deles como confiável. Ele valida o plano inteiro antes de baixar um único byte, e nunca deixa um valor de manifesto chegar a um shell.

Esta página é a história completa de confiança. Veja [[Feed Format]] para o schema do manifesto que ela valida, e [[Engine]] para onde essas checagens ficam na transação DIFF -> FETCH -> APPLY -> COMMIT.

---

## A ideia central: fail-closed, antes de qualquer coisa acontecer

`validate_plan()` roda dentro da fase `check`/diff, **antes** de qualquer fetch e **antes** de qualquer apply. Ele percorre cada entrada na árvore de arquivos planejada e cada entrada em `delete[]`, e se qualquer entrada isolada estiver malformada ele **rejeita o manifesto inteiro** e a transação nunca começa. Não há aceite parcial, não há "pula a ruim e aplica o resto". Um campo ruim envenena o lote, de propósito.

Um manifesto é aceito apenas se **todas** estas condições valem para **cada** entrada:

| Campo | Regra | Por que |
|---|---|---|
| `path` | não absoluto, sem componente `..`, sem componente `.`, sem `./` inicial, sem `/./` embutido, sem barra final, sem caractere de controle (tab / newline) | um caminho deve permanecer dentro de `MODULE_DIR`; um caminho absoluto ou `..` é escrita em qualquer lugar |
| `sha256` | corresponde a `^[0-9a-f]{64}$` exatamente | um sha não hex seria de outra forma interpolado em um caminho de shell; ele é o endereço de conteúdo, então deve ser um digest hex puro e nada mais |
| `mode` | apenas octal (`[0-7]`) | uma string de mode vira um argumento de `chmod` |
| `size` | apenas dígitos, e `<=` o teto de tamanho do motor | limita o download e a descompressão |
| `class` | exatamente `live`, `soft` ou `reboot` | a classe decide se um arquivo aplica ao vivo ou é estagiado para reboot |
| `enc` | exatamente `raw` ou `gz` | o encoding decide se o blob é descomprimido com gunzip |
| entradas de `delete[]` | as mesmas regras de caminho acima | uma entrada de `delete[]` dirige uma remoção; um `..` não verificado seria um `rm` fora da árvore |

Como isso roda primeiro, um manifesto envenenado nunca pode escrever fora do módulo, nunca pode deletar fora do módulo e nunca pode injetar um token não hex em uma linha de comando.

### Valores de manifesto nunca tocam um shell

A segunda metade da regra: mesmo depois que um valor passa na validação, ele nunca é interpolado em `sh`, e nunca alimentado a `awk system()`. O comando check foi deliberadamente reescrito para não conter nenhuma chamada `system()`. O endereçamento por conteúdo faz o resto do trabalho: um blob é buscado por seu `sha256`, gravado em um caminho de cache nomeado por esse mesmo `sha256`, e os bytes baixados são re-hasheados e comparados antes de qualquer coisa ser aplicada. Um valor que não é um digest limpo de 64 hex nunca chega tão longe, porque o `validate_plan()` já o rejeitou.

### Uma segunda linha de defesa no momento do apply

`validate_plan()` bloqueia `..` **lexicamente**, mas um symlink pré-existente já dentro da árvore ainda poderia redirecionar uma escrita. Então no momento do apply o `contained()` resolve o caminho de alvo real e confirma que ele está sob a base do módulo, falhando closed quando não consegue resolver. Escritas são atômicas (escreve em um nome temporário, depois `rename` sobre o alvo) e toda sobrescrita é salva em backup para `rollback/` primeiro; um backup que falha aborta o apply em vez de sobrescrever sem rede de segurança.

---

## Os dois perfis

O VDLU roda em um de dois perfis de confiança, definido por `profile=` na config.

### `hardened` (o padrão público)

- **A assinatura é obrigatória.** O manifesto deve carregar uma assinatura ed25519 válida de uma chave no keyring do dispositivo, ou a transação aborta.
- **Downgrade é bloqueado.** Um manifesto cuja `version` é menor que a versão instalada é recusado. Um atacante não pode revertê-lo para um build sabidamente vulnerável.
- Este é o perfil para qualquer módulo distribuído ao público sobre `https://`.

### `trusted` (privado, fonte SSH-staged)

- A verificação de assinatura é **best-effort**: a fonte é um feed privado `file://` ou SSH-staged que você controla, então uma assinatura faltando ou não verificável não aborta de imediato.
- **Mas o `sha256` de todo blob ainda é sempre conferido.** `trusted` relaxa *quem assinou o manifesto*, nunca *se os bytes batem com o plano*. A integridade de conteúdo é inegociável em ambos os perfis.

---

## Fail-closed por inversão

Esta é a parte sutil, e é a parte que a maioria dos sistemas erra.

`trusted` é a **única** string que opta por verificação relaxada. O motor não testa "isto é `hardened`?" Ele testa "isto **não** é `trusted`?":

```sh
prof=$(cfg profile hardened | tr -d '[:space:]')
...
if [ "$prof" != trusted ]; then
    # signature mandatory
fi
```

Então **qualquer coisa** diferente do literal `trusted` resolve para o comportamento hardened:

- a linha está inteiramente ausente -> hardened
- um typo como `hardend` -> hardened
- `trusted ` com um espaço no fim, ou um `\r` de CRLF -> hardened
- `Trusted` com caixa errada -> hardened
- um valor adulterado por MITM -> hardened

Uma versão anterior defaultava uma linha *ausente* para hardened, o que ainda deixava um *valor* corrompido cair para o caminho aberto. Isso era um fail-open: uma string de perfil adulterada poderia aceitar silenciosamente um manifesto não assinado, e um manifesto não assinado significa um `.so` fornecido por atacante trocado sob MITM, o que é execução remota de código em nível root. A inversão fecha isso. A única forma de obter verificação relaxada é soletrar `trusted` exatamente, e mesmo então os hashes dos blobs são conferidos. O motor nunca está a um typo de aceitar código não assinado. (O `tr -d` remove espaço em branco perdido para que um `trusted` legítimo com espaçamento desleixado não seja erroneamente rejeitado, sem reabrir o buraco.)

**Este teste é load-bearing. Ele deve permanecer `!= trusted` e nunca virar `== hardened`.**

---

## O manifesto é vinculado ao módulo

Uma única chave de release assina muitos módulos. Então um manifesto que é validamente assinado, para um módulo *diferente*, poderia em princípio ser servido para este (uma má configuração de feed, uma troca de fonte ou um redirecionamento MITM) e sua assinatura passaria na checagem.

O VDLU fecha isso com um vínculo: o campo assinado `module` dentro do manifesto deve ser igual ao `MODID` desta instalação, ou o manifesto é rejeitado como um feed de módulo cruzado. Como `module` está dentro da forma canônica assinada, um atacante não pode mudá-lo sem quebrar a assinatura. Um feed validamente assinado para o módulo B simplesmente não pode ser aplicado ao módulo A.

---

## O verificador enxuto no dispositivo

A verificação no dispositivo usa **ed25519-mini**, um checador minúsculo somente de verificação construído sobre o TweetNaCl (domínio público). **Não há `openssl` no dispositivo**.

- A entrada de keyring é a **chave pública de 32 bytes brutos**, armazenada como `keyring/<key_id>.pub`. (A chave pública PEM é um artefato do lado do PC apenas; copiar um PEM para o keyring do dispositivo quebra a verificação, já que o verificador espera exatamente 32 bytes brutos.)
- `vdlu-verify <manifest.json> <keyring_dir>` reconstrói a forma canônica (o texto do manifesto com o campo `sig` removido, compacto, chaves ordenadas), faz o hash dele para a mensagem hex de 64 caracteres que a assinatura cobre, decodifica a assinatura base64, confere que ela tem 64 bytes e pergunta a `ed25519-mini <pub32> <msg> <sig64>` por um veredito. rc 0 = válido, qualquer outra coisa = rejeitar.
- O binário é estático por ABI (arm64-v8a, armeabi-v7a, x86, x86_64), com um `PROVENANCE.json` fixando as fontes exatas do TweetNaCl, o hash do wrapper e as flags de build, de modo que a coisa rodando como root é auditável.
- O `key_id` do manifesto é ele próprio sanitizado (sem `/`, sem `..`, sem aspas) antes de ser usado para escolher um arquivo de keyring, então ele não pode escapar do diretório de keyring.

### O keyring é flash-only, verify-not-copy, estável

O keyring vem dentro do módulo no momento do flash e não é reescrito pelo motor de atualização. Na re-vendorização a regra é **verify, do not copy**: o keyring muda apenas em uma rotação de chave deliberada, nunca como efeito colateral de uma atualização.

### A rotação de chave não brica instalações antigas

Quando uma chave de assinatura é rotacionada, o keyring traz **tanto a chave pública bruta atual quanto a anterior**. O verificador seleciona o arquivo de chave pelo `key_id` do manifesto, então um feed ainda assinado pela chave antiga verifica contra a pubkey antiga, e um feed assinado pela chave nova verifica contra a nova. Um dispositivo que não atualizou além da rotação continua funcionando; nada fica órfão.

---

## A lista de permissão de key_id para atualização de módulo

A rotação de chave já significa que o keyring pode legitimamente conter mais de uma chave, e um módulo pode conter mais de uma por um segundo motivo: ele pode trazer uma chave de menor confiança que assina um feed *diferente*. O feed de fingerprint é exatamente esse caso. Um módulo pode carregar uma chave estreita cujo único trabalho é assinar um feed de fingerprint, sentada no mesmo keyring bem ao lado da chave de release que assina o próprio módulo.

Isso levanta uma questão que a história da rotação sozinha não responde: uma vez que duas chaves vivem no keyring, *qual* delas tem permissão para assinar uma **atualização de módulo**? Uma atualização de módulo é a coisa mais poderosa que um manifesto pode pedir, porque reescreve arquivos que o dispositivo executa como root. O verificador costumava pegar a pubkey nomeada pelo `key_id` do manifesto e aceitar qualquer chave que por acaso estivesse presente no keyring. Então a chave de feed de fingerprint de menor confiança, se vazasse, poderia assinar um manifesto de atualização de módulo e o dispositivo o honraria. Isso é um bypass da raiz de confiança: uma chave destinada a um trabalho estreito poderia conduzir uma atualização root flashless completa.

A correção fixa o `key_id` de atualização de módulo aceito a uma **lista de permissão** fail-closed, conferida **antes** de a pubkey sequer ser selecionada. A chave de config é `key_id`, e o motor a resolve assim:

- **Um keyring de chave única fixa essa única chave automaticamente.** O caso comum não precisa de config nenhuma: se o keyring contém exatamente uma chave, essa chave *é* a lista de permissão, e nada mais pode assinar uma atualização de módulo.
- **Um keyring de múltiplas chaves deve definir `key_id`.** No momento em que uma segunda chave aparece, o motor se recusa a adivinhar. Ele falha fechado com "multiple keys in keyring; config must pin key_id" até que a config nomeie a chave (ou chaves, separadas por vírgula durante uma janela de rotação) que pode assinar atualizações de módulo.

Como a checagem roda antes da seleção da pubkey, um manifesto que nomeia uma chave que está presente mas não na lista de permissão é rejeitado sem o verificador jamais carregar essa chave. O conjunto resolvido é espelhado para o `vdlu-verify` através do `VDLU_KEYID_ALLOW`, então o checador enxuto no dispositivo impõe a mesma fixação e os dois não podem divergir. Isso vale em **ambos** os perfis: tanto `hardened` quanto `trusted` consultam a lista de permissão, porque a lista de permissão decide *qual chave* é uma raiz de atualização de módulo válida, não *se* uma assinatura é exigida.

O feed de fingerprint mantém sua própria raiz de confiança fixada separada, `FEED_KEY_ID`. É uma raiz distinta com um trabalho distinto, nunca alcançável pelo caminho de atualização de módulo acima, então fixar a lista de permissão de atualização de módulo não a toca e uma chave de feed vazada ainda não pode assinar uma atualização de módulo. Essa mudança elevou `ENGINE_VERSION` para 4.

---

## O que o tools-manifest fecha

O bootstrap enxuto de fetch baixa um `curl` estático no primeiro uso para módulos que não trazem o seu próprio. Como esse binário roda como root, sua própria assinatura de manifesto (ed25519-mini) e seu hash são **obrigatórios em qualquer perfil**, incluindo `trusted`, antes de ele ser instalado ou executado. A webview é apenas transporte; a confiança vem da assinatura e da checagem de hash no dispositivo, nunca do fato de que um download teve sucesso.

---

## O que um atacante NÃO PODE fazer

Mesmo sendo dono do feed, ou sentado no fio como um MITM completo, um atacante não pode:

- **Escrever fora do módulo.** Caminhos absolutos, `..`, `.`, caracteres de controle e barras finais são todos rejeitados antes de qualquer apply, e o redirecionamento por symlink é pego de novo no momento do apply.
- **Deletar fora do módulo.** Entradas de `delete[]` passam pela mesma validação de caminho.
- **Injetar um comando.** Nenhum valor de manifesto é interpolado em um shell ou `awk system()`; `sha256` deve ser hex puro de 64 ou o manifesto inteiro é rejeitado.
- **Enviar código não assinado para uma instalação pública.** O `hardened` torna a assinatura obrigatória, e o perfil é fail-closed por inversão, então nenhum typo ou valor adulterado rebaixa isso.
- **Assinar uma atualização de módulo com uma chave de menor confiança.** O `key_id` de atualização de módulo é fixado a uma lista de permissão fail-closed, conferida antes de a pubkey ser selecionada, então uma chave de feed de fingerprint vazada compartilhando o keyring não pode assinar uma atualização root completa.
- **Servir o feed assinado de outro módulo aqui.** O campo assinado `module` deve ser igual a este `MODID`.
- **Revertê-lo.** Downgrade é bloqueado em `hardened`.
- **Corromper um blob sem detecção.** Todo blob baixado é re-hasheado contra o `sha256` do manifesto em ambos os perfis; uma divergência depois de três tentativas aborta a fase sem nada aplicado.
- **Trocar por um fetcher root falso.** O `curl` bootstrapado tem a assinatura e o hash conferidos antes de ser instalado ou executado, em todo perfil.
- **Aplicar pela metade uma atualização corrompida.** A transação só alcança `DONE` quando um re-hash de tudo bate; um apply que falha reverte em vez de sobrescrever sem um backup.

---

Veja também: [[Feed Format]] para o schema do manifesto, [[Engine]] para a transação em que essas checagens vivem, e [[Architecture]] para a visão geral.
