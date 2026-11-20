# Contributing

Contribuições são bem-vindas. O VDLU é um motor de autoatualização flashless e incremental
vendorizado em módulos KernelSU / APatch / Magisk. Esta página é o workflow prático de dev;
para como as peças se encaixam, leia [[Architecture]], [[Engine]] e
[[Producer]] primeiro.

## Nada compila

O VDLU são scripts (`sh` POSIX, um pouco de Python do lado do release, JS vanilla para a
WebUI), então não há passo de build. Você verifica uma mudança rodando o pipeline
de ponta a ponta e fazendo static-check de cada peça.

## Contrato de junção primeiro

O contrato de interface entre os componentes (as assinaturas de CLI, nomes de arquivo e
chaves JSON compartilhadas pelo motor, pelo producer e pela WebUI) é a **lei da
convergência**. Trate-o como imutável. Se sua mudança toca a junção
producer-para-engine (schema do manifesto, schema do journal, chaves de config, a
regra de assinatura/canonicalização), **alinhe o contrato de interface primeiro**, depois
mude o código em ambos os lados para corresponder. Uma mudança de um lado da junção sem
o outro quebra silenciosamente os adotantes. Veja [[Producer]] para a regra de canonicalização
na qual o assinador e o verificador devem concordar byte a byte.

## Teste de ponta a ponta antes de um PR

Rode o producer e o motor juntos em uma árvore descartável, da mesma forma que o
release de um adotante faz:

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

Depois faça static-check de cada componente:

```sh
sh -n engine/*.sh            # POSIX sh syntax, must pass
node --check webui/vdlu.js   # WebUI JS syntax
```

E abra `webui/demo.html` em um navegador: ele mocka a ponte do root manager
(`ksu.exec`), então você pode exercitar o painel de Updates, o toast de progresso, o cancelamento
e o banner de reinício sem dispositivo. Veja [[WebUI]].

## Regras da casa

- **`sh` POSIX no dispositivo.** Sem bashismos além de `local`, e sem `jq`. Tem que
  rodar em toybox / busybox.
- **Segurança é inegociável.** Todo campo do manifesto é entrada hostil;
  o `validate_plan()` permanece fail-closed, e a chave de assinatura privada nunca toca
  CI ou um dispositivo. Não afrouxe uma checagem para fazer um teste passar.
- **Rigor na falha.** Mantenha a transação resumível: nada reporta "done"
  sem um re-hash correspondente, nada é sobrescrito sem um backup, e
  os applies permanecem atômicos.
- **Sempre qualidade de release.** Mantenha comentários concisos; sem comentários gratuitos.
- **Uma mudança lógica por PR.** Diga o que mudou e por que.

## Abrindo issues

Abra uma issue descrevendo o que você fez, o que esperava e o que aconteceu.
Para um bug, inclua o id do módulo, o perfil da fonte (`hardened` ou `trusted`),
o comando `update.sh` que você rodou, e o `journal.json` relevante (ele registra a
fase, o estado e o erro). Para uma feature, diga qual componente ela toca (engine,
producer ou WebUI) para que o impacto na junção fique claro de antemão.
