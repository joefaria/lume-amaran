# Guia técnico do Lume

[← Voltar à apresentação](../README.md)

Pareamento direto, comportamento dos controles, dados locais e desenvolvimento. Para instalar e conectar sua luz, comece pelo [README](../README.md#comece-em-poucos-passos).

## Importação opcional de uma configuração existente

O app precisa conhecer os dados da rede Bluetooth existente. A busca por Bluetooth não recupera essas informações.

Em **Já tenho uma configuração… → Sidus Link / arquivo…**, o importador aceita:

1. Um JSON compatível do Sidus contendo `netKeys`, `appKeys` e `nodes`, com uma rede e uma chave de aplicação. Também aceita exportações de `wesbos/amaran-BLE-control` e `neyako/amaran-hacs`.
2. Uma pasta de backup local **já existente e não criptografado** do iPhone. O importador consulta apenas os JSON de iluminação em `Documents/mesh/` dos domínios do Sidus Link/Sidus Link Pro. Outros aplicativos e arquivos pessoais não são lidos.

**Backups criptografados ainda não são suportados por este importador. Não desative a criptografia para usar o app.** Uma extração local específica e com senha pode ser preparada em uma próxima etapa, caso esse seja o caminho escolhido. A presença desses JSON varia por versão do Sidus e precisa ser confirmada no backup real.

O fluxo alternativo **Usar amaran Desktop…** lê uma configuração local do aplicativo oficial. Ele não instala nem abre o aplicativo oficial, nem importa automaticamente dados do Sidus do iPhone. Caso a luz precise ser pareada novamente no aplicativo oficial, isso exige uma decisão separada do usuário.

Depois de importar, selecione sua amaran 60x S. Ligue a luz, aproxime o Mac e conecte. A identidade da rede e as mensagens são autenticadas. Os controles só são liberados depois que a luz responde com seu estado. Se o Sidus Link estiver ocupando a conexão, pode ser necessário fechá-lo durante o teste.

## Comportamento

- Abrir o app consulta o estado, mas nunca acende a luz nem aplica brilho/temperatura anteriores.
- Apagar refere-se ao emissor; a luz continua energizada para receber Bluetooth.
- Os ajustes rápidos alteram brilho e temperatura com a luz já acesa; não ligam o emissor automaticamente.
- Os sliders continuam ativos enquanto a confirmação acontece em segundo plano, sem mensagem de Aplicando. Movimentos rápidos guardam o último valor de cada controle e enviam uma atualização de cada vez. Uma resposta anterior não substitui o valor que você está arrastando.
- Uma falha real continua visível. Sem confirmação em cinco segundos, os ajustes pendentes são descartados e os controles retornam ao último estado recebido, preservando um arrasto em andamento.
- Reconexão após uma queda é manual nesta versão, pelo botão Reconectar.
- Mudanças são enviadas ao soltar o slider, evitando uma sequência excessiva de comandos.

## Dados locais

As credenciais geradas no pareamento ou importadas ficam no Chaves do macOS, em `dev.jonatas.lume.bluetooth`. Não são impressas em logs nem incluídas na entrega.

Cada rede recebe um endereço de origem independente na faixa `0x7000…0x7FFE`, preservado entre execuções. Os contadores são gravados antes de cada envio, em `~/Library/Application Support/Lume/sequence-<networkID>.json`, com permissão `0600`. Esse arquivo não contém as chaves da rede. Nunca reiniciamos o contador silenciosamente quando um arquivo está corrompido. A comunicação só começa após receber um beacon autenticado da rede.

O controle da luz acontece localmente por Bluetooth. Links externos de ajuda, comunidade e autoria abrem no navegador quando clicados.

## Desenvolvimento

```sh
zsh test.sh
zsh build.sh
# O aplicativo compactado fica em dist/Lume-macOS.zip
```

Requer Command Line Tools com Swift moderno e Node somente para gerar os vetores independentes dos testes. O aplicativo entregue é um executável nativo sem essas dependências.

Os testes verificam CMAC NIST, AES-CCM comparado ao OpenSSL do Node, rejeição de mensagens adulteradas, identificação da rede, beacon autenticado, pacotes completos, comandos de referência, limites da 60x S, importação dos formatos suportados, seleção de arquivos de backup e persistência dos contadores entre reinícios. O pareamento é exercitado de ponta a ponta com um dispositivo simulado por outra chave P-256, confirmação do transcript, descriptografia dos dados de rede, derivação de DeviceKey, mensagens fora de ordem e rejeição de autenticação inválida. A configuração testa fragmentação, recomposição fora de ordem, confirmação de segmentos e vínculo ao modelo de controle. Nenhum desses testes substitui a validação com a luz real.

Para inspecionar a interface sem Bluetooth:

```sh
/caminho/para/Lume.app/Contents/MacOS/Lume --render /caminho/preview.png connected
```

Os estados `connected`, `setup`, `offline`, `pending` e `error` geram imagens com dados ilustrativos e encerram o processo. O renderizador é uma prévia de layout e pode não capturar fielmente o vidro e a vibrância do compositor do macOS. As imagens `preview-light.png` e `preview-dark.png` mostram o painel nativo.

## Fontes

- https://github.com/wesbos/amaran-BLE-control — codificação Telink e referência de transporte (MIT).
- https://github.com/neyako/amaran-hacs — beacon autenticado, filtro de proxy, isolamento dos endereços e leitura de estado (MIT).
- https://github.com/aarondfrancis/amaran/blob/main/scripts/sidus-backup-import — referência de localização e formato dos JSON do Sidus em backups iOS; implementação do importador feita em Swift neste projeto.
- https://help.amarancreators.com/en/amaran-60xs/controls — limites documentados da 60x S.
- https://www.bluetooth.com/blog/provisioning-a-bluetooth-mesh-network-part-2/ — etapas de autenticação e distribuição dos dados de pareamento PB-GATT.

Os avisos das implementações MIT estão em [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) e dentro do app. O motor REA não foi utilizado: esta etapa trabalha com código-fonte público já disponível, não com decompilação de um aplicativo proprietário.
