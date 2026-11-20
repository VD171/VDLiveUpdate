# FAQ

Respostas curtas para as perguntas que surgem com mais frequência. Cada uma leva à página com
a história completa.

## O que significa "flashless"? Eu ainda flasho da primeira vez?

Sim, você flasha uma vez. O módulo é instalado da forma normal (flashe o zip no
seu root manager). "Flashless" descreve toda atualização depois disso: o VDLU busca
apenas os arquivos que mudaram e os aplica no lugar, então você nunca reflasha um
zip completo só para enviar algumas linhas alteradas. Veja [[Architecture]].

## Uma atualização precisa de reinício?

Normalmente não. A maioria dos arquivos (sua WebUI, binários, bibliotecas, configs, `module.prop`)
são de classe **live** e aplicam atomicamente sem reinício. Apenas arquivos de classe reboot
(um `.so` sob `zygisk/`, um overlay `/system/**`, um arquivo sepolicy `*.rule`) são
**estagiados** e trocados no próximo boot, porque um processo rodando já
mapeou o inode ao vivo. Quando isso acontece a WebUI mostra um banner persistente
"reboot to activate". Veja [[Reboot Handling]].

## É seguro se o feed sofrer MITM ou for envenenado?

Sim, em um feed `hardened`. Todo campo do manifesto é tratado como entrada hostil.
O manifesto deve carregar uma assinatura ed25519 válida sobre sua forma canônica, e
o `validate_plan()` roda fail-closed **antes de qualquer download**: ele rejeita o manifesto
inteiro em um caminho absoluto ou `..`, um `sha256` que não tem 64 caracteres hex,
ou um mode, class ou encoding inválido. O manifesto também é vinculado ao id do seu módulo,
de modo que um feed validamente assinado para um módulo diferente não pode ser servido em seu lugar.
O sha256 de todo blob é verificado após o download independentemente do perfil. Veja
[[Security and Trust Model]].

## O que ele precisa no dispositivo (dependências)?

Muito pouco. `sh` POSIX puro (mksh / busybox / toybox) mais o `sha256sum`,
`gzip`, `base64` e `date` do toybox; o verificador `ed25519-mini` embarcado; e, apenas para
uma fonte `https`, um `curl` estático que é buscado uma vez e cacheado no Tier-2.
Uma fonte `file://` não precisa de curl de forma alguma. **Não há dependência de `jq`**: o
motor parseia JSON com um flattener estilo gron escrito em `awk`. Veja [[Engine]].

## O openssl é necessário no dispositivo?

Não. O `openssl` é usado apenas do lado do PC/release (`vdlu-keygen`, `vdlu-sign`).
No dispositivo, a verificação de assinatura usa o binário `ed25519-mini` embarcado e
enxuto, que lê uma chave pública RAW de 32 bytes. Veja [[Producer]] e
[[Security and Trust Model]].

## Como eu rotaciono a chave de assinatura?

Gere um novo par de chaves com `vdlu-keygen`, adicione a nova chave pública RAW de 32 bytes ao
keyring do dispositivo ao lado da anterior, e comece a assinar com o novo
`key_id`. O dispositivo escolhe `<keyring>/<key_id>.pub` pelo `key_id` do manifesto,
então nenhuma mudança no motor é necessária. Enviar tanto a chave pública atual quanto a anterior
significa que uma chave rotacionada nunca brica instalações antigas. Como uma rotação deixa mais de uma chave no keyring, você também deve fixar qual chave pode assinar uma atualização de módulo: defina a config `key_id` (separada por vírgula durante a janela de rotação). Um keyring de chave única fixa automaticamente e não precisa de config. Veja [[Security and Trust Model]].

## hardened vs trusted - qual eu uso?

Use `hardened` para qualquer feed público (servido sobre `https`, por exemplo GitHub Pages).
Ele torna a assinatura obrigatória e bloqueia downgrades. Use `trusted` apenas para uma
fonte privada `file://` ou SSH-staged que você já controla, onde a assinatura
é best-effort (o hash de todo blob ainda é conferido). Na dúvida, use `hardened`:
ele é o padrão fail-closed, e qualquer valor não `trusted` é tratado como
`hardened`. Veja [[Security and Trust Model]].

## E se um blob for adulterado ou o manifesto estiver malformado?

A atualização aborta e nada é aplicado. Um manifesto malformado é rejeitado inteiro
pelo `validate_plan()` antes de qualquer fetch. Um blob cujo sha256 não corresponde ao
manifesto é rejeitado; três falhas no mesmo blob abortam a fase de fetch com
nada aplicado. Em qualquer falha grave o journal registra `ERROR` e o módulo
é deixado intacto. Veja [[Engine]].

## Uma atualização pode deletar meus arquivos ou bricar o dispositivo?

O risco é contido por design. Arquivos sobrescritos e deletados são primeiro salvos em
backup para `rollback/<version>/`, e o `apply` aborta em vez de sobrescrever sem um
backup bem-sucedido. Deletes rodam apenas quando uma transação alcança `DONE`, nunca
enquanto um reinício ainda está pendente. Um apply que falha reverte os arquivos ao vivo que já
gravou. Caminhos são validados para contenção dentro do diretório do módulo antes do uso,
de modo que um manifesto não pode escrever ou deletar fora da árvore. Veja [[Engine]] e
[[Security and Trust Model]].

## Ele funciona no KernelSU E no Magisk E no APatch?

Sim. O VDLU é `sh` POSIX comum mais uma WebUI, vendorizado no módulo, então ele roda no
KernelSU, APatch e Magisk igualmente. Ele usa a ponte de WebUI do root manager
(`ksu.exec`) para dirigir o motor e fazer poll do progresso. Veja [[Architecture]] e
[[WebUI]].

## Qual o tamanho da pegada no dispositivo?

Pequena. O motor são scripts; os únicos binários são o verificador `ed25519-mini`
por ABI (minúsculo) e, para uma fonte `https`, um `curl` estático (~1MB) que é
buscado uma vez e cacheado. Um módulo que já agrega seu próprio `curl` o reusa
e não adiciona nenhum download. O cache de blobs do Tier-2 guarda conteúdo verificado mais
as últimas 3 versões de rollback. Veja [[Engine]] e [[Architecture]].
