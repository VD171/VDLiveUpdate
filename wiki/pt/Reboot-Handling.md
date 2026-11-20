# Reboot Handling

O propósito inteiro do VDLU é atualizar um módulo sem reflashá-lo e, sempre que possível, sem reiniciar de forma alguma. A maioria dos arquivos em um módulo pode ser substituída enquanto o dispositivo está rodando. Alguns genuinamente não podem, porque o kernel ou o processo zygote já os mapeou e não notará uma mudança até o próximo boot.

A função do VDLU é distinguir esses dois grupos automaticamente, aplicar tudo que ele seguramente pode **ao vivo**, e adiar apenas os arquivos genuinamente presos ao boot para um reinício que ele sinaliza com clareza. Esta página explica como.

Para a mecânica do motor por baixo disso, veja [[Engine]]. Para a visão geral, veja [[Architecture]].

## Por que não simplesmente reiniciar toda vez

Um reinício é a coisa mais cara que uma atualização pode pedir a alguém. Ele interrompe o que a pessoa está fazendo, leva um minuto ou mais, e treina as pessoas a temer atualizações. Um bom atualizador incremental deve parecer invisível: você toca atualizar, alguns arquivos mudam sob o sistema rodando, e você já está na nova versão.

Então o VDLU inverte a premissa usual. O padrão é ao vivo. Um arquivo é adiado para um reinício apenas quando ele é comprovadamente um dos tipos presos ao kernel ou ao zygote, e mesmo então apenas aquele arquivo espera. Tudo ao redor dele ainda atualiza imediatamente.

## As três classes

Todo arquivo no feed recebe uma classe. O producer pode defini-la explicitamente no manifesto, mas na prática a classe é derivada do caminho, e o motor só vai promover um arquivo em direção a `reboot`, nunca rebaixá-lo em direção a `live`. As classes são:

**LIVE** é o caso comum: assets de web UI, binários, scripts lidos sob demanda, arquivos de config, `module.prop` e qualquer outra coisa não correspondida pelas regras abaixo. Um arquivo live é salvo em backup e então atomicamente renomeado sobre o alvo enquanto o sistema roda. Sem reinício, e a mudança está em vigor no momento em que o rename aterrissa.

**SOFT** são os scripts de ciclo de vida do próprio módulo: `service.sh`, `post-fs-data.sh` e `boot-completed.sh`. Esses são aplicados ao vivo exatamente como arquivos LIVE, então a nova cópia já está em disco. A razão de eles ganharem sua própria classe é que o sistema rodando já executou a cópia antiga neste boot; a nova simplesmente roda no próximo boot, sem staging e sem banner. Não há nada a adiar, apenas um repasse natural.

**REBOOT-hard** é o pequeno conjunto que não pode mudar sob um sistema rodando:

- bibliotecas nativas, `*.so` (qualquer coisa sob um caminho `zygisk/`), porque o zygote as mapeia em todo app na inicialização;
- arquivos de overlay de `/system`, porque o overlay é montado no boot;
- arquivos `sepolicy.rule`, porque a política SELinux é carregada cedo.

Um arquivo REBOOT-hard nunca é gravado sobre seu inode ao vivo enquanto o sistema está de pé. Sobrescrever um `.so` que o zygote já mapeou é como você consegue crashes e estado inconsistente. Em vez disso o novo conteúdo é **estagiado** ao lado do diretório de estado e trocado no próximo boot, antes que qualquer coisa possa mapeá-lo.

## Do caminho à classe, de relance

O motor deriva a classe a partir do caminho assim:

| Padrão de caminho | Classe | Aplicado |
|---|---|---|
| `zygisk/**`, `**/zygisk/**` (os arquivos `.so`) | REBOOT-hard | estagiado, trocado pré-zygote no boot |
| `system/**` (overlay) | REBOOT-hard | estagiado, trocado no boot |
| `*.rule` (sepolicy) | REBOOT-hard | estagiado, trocado no boot |
| `service.sh`, `post-fs-data.sh`, `boot-completed.sh` | SOFT | gravado ao vivo, roda no próximo boot |
| `webroot/**`, `bin/**`, `lib/**`, configs, `module.prop`, todo o resto | LIVE | gravado ao vivo, efetivo imediatamente |

O manifesto pode carregar uma `class` explícita por arquivo, mas a classe derivada age como um piso: se um arquivo parece REBOOT-hard pelo seu caminho, ele é tratado como REBOOT-hard mesmo que o manifesto diga o contrário. Isso impede um feed mal rotulado de algum dia tentar fazer hot-swap de um `.so`.

## Como um run lida com os dois grupos ao mesmo tempo

Durante um `run` normal (o ciclo DIFF para FETCH para APPLY para COMMIT descrito em [[Engine]]), os dois grupos são tratados na mesma transação:

```
run:
  LIVE + SOFT  --> backup -> write .vdlu-tmp -> verify -> atomic rename   (effective now)
  REBOOT-hard  --> materialize into staged/<path>.vdlu-new                (live inode untouched)

  re-hash every LIVE + SOFT file
       |
       +-- nothing staged  --> DONE
       +-- something staged --> PENDING_REBOOT  (reboot banner in the WebUI)
```

Então depois de um run que tocou um `.so`, você já está na nova versão para todo arquivo live, e apenas as peças estagiadas estão esperando. O journal reporta `reboot_pending`, e a WebUI mostra um banner persistente convidando a um reinício para ativar os arquivos estagiados. Não há "done" falso: um run com arquivos estagiados termina em `PENDING_REBOOT`, não `DONE`.

## A troca no boot

Os arquivos estagiados são aplicados pelo comando `boot`, que o módulo host liga a `post-fs-data.sh` para que ele rode sincronamente e **pré-zygote**, antes que qualquer processo possa mapear o novo `.so`.

`boot` faz um `resume` (para terminar qualquer fase interrompida) e então a troca. Para cada arquivo REBOOT-hard estagiado ele:

1. confirma que o caminho estagiado permanece dentro do diretório do módulo (uma checagem de contenção);
2. re-hasha `staged/<path>.vdlu-new` contra o hash do manifesto;
3. faz backup do arquivo ao vivo atual;
4. `mv -f` o arquivo estagiado sobre o ao vivo e dá `chmod` nele;
5. re-hasha o arquivo agora no lugar, para confirmar que a troca aterrissou corretamente;
6. marca como aplicado.

Apenas depois que todo arquivo estagiado trocou e re-verificou a transação fecha de `PENDING_REBOOT` para `DONE`. Se qualquer passo falha, o journal registra o erro e o módulo mantém seus arquivos anteriores; nada é deixado meio trocado.

Como a troca é uma sequência de re-hashes e renames atômicos, rodar `boot` é seguro mesmo se ele foi interrompido da última vez. Ele simplesmente pega os arquivos estagiados de volta.

## auto_on_reboot

O staging é apenas metade de uma sensação sem reinício; a outra metade é que o usuário nunca deveria ter que lembrar de rodar a troca. Com `auto_on_reboot=1` na config, o `post-fs-data.sh` do módulo host chama `update.sh boot` em todo boot. Isso significa:

- se uma transação está pendente de reinício, os arquivos estagiados são trocados automaticamente antes de o zygote iniciar, e o usuário simplesmente se encontra inteiramente na nova versão;
- se não há nada pendente, `boot` pode rodar um ciclo novo e aplicar tudo, incluindo um `.so`, naquele único boot, já que ele já está rodando pré-zygote.

Em outras palavras, um `.so` estagiado não custa nada ao usuário além de um reinício que ele ia fazer de qualquer jeito. Ele não precisa tocar em nada na segunda vez.

## Offline no boot, sem drenar a bateria

Às vezes o `boot` quer conferir o feed mas o dispositivo ainda não tem rede. O VDLU pode esperar por ela, paciente e barato, controlado por `boot_retry_minutes` (0 o desliga). A espera é deliberadamente segura para a bateria:

- entre tentativas ele simplesmente dá `sleep`, que congela em deep sleep, então o dispositivo dorme normalmente e a retentativa resume apenas quando o dispositivo já está acordado;
- ele não segura wakelock e não segura o lock do motor enquanto espera, então um run manual nunca é bloqueado;
- antes de cada tentativa ele confere se a rede é permitida com um lookup de rota do kernel que não envia pacote e não acorda o rádio;
- ele nunca retenta uma falha determinística como uma assinatura ruim ou um downgrade bloqueado, apenas uma condição genuína de rede-ausente.

O check do manifesto em si permanece gratuito em qualquer rede, então você sempre descobre que uma atualização existe; apenas o download espera a política de rede ser satisfeita, adiando de forma limpa em vez de errar.

## Veja também

- [[Engine]]: a transação, a lógica de apply-por-classe e o comando `boot` por completo.
- [[Architecture]]: onde o motor fica entre o producer e a WebUI.
