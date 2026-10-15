# Lume · controle da amaran na barra de menus

Aplicativo nativo de macOS, escrito em Swift/SwiftUI e CoreBluetooth, preparado para a amaran 60x S. Faz o pareamento diretamente com a luz e não exige celular, Sidus Link, amaran Desktop, Node, Python ou servidor web durante o uso.

Projeto independente, sob [licença MIT](LICENSE), sem vínculo oficial com amaran ou Aputure.

[English](README.md) · [Compatibilidade e adaptação de modelos](COMPATIBILITY.md) · [Como contribuir](CONTRIBUTING.md)

## Download

Baixe `Lume-macOS.zip` em [Releases](https://github.com/joefaria/lume-amaran/releases), descompacte e abra `Lume.app`. O executável é para Apple Silicon (M1 ou posterior), com destino mínimo de macOS 13. Não há versão Intel validada. A interface está em português.

## Compatibilidade

**Validado com a amaran 60x S. Outros modelos ainda não foram testados com o Lume.** A base Bluetooth pode ser adaptada, mas o código atual fixa a faixa em 2700–6500 K e controla uma luz. Não inclui RGB/HSI, efeitos ou grupos. O nome 60x S mostrado para um dispositivo genérico não é detecção automática de modelo. Consulte [COMPATIBILITY.md](COMPATIBILITY.md) antes de testar outra luz.

## Estado desta entrega

- App compilado e assinado localmente para Apple Silicon, macOS 13 ou posterior.
- Ícone na barra de menus, popover, preferências e busca Bluetooth conferidos no Mac.
- Controles implementados: acender/apagar o emissor, intensidade de 0 a 100%, temperatura de 2700 a 6500 K e três ajustes rápidos.
- Pareamento PB-GATT completo, configuração do controle amaran e importação opcional implementados.
- 89 testes locais de protocolo, autenticação, pareamento, persistência e sequência de comandos passaram. Há um teste de duas pontas com chaves P-256 independentes, rejeição de confirmação adulterada e transporte segmentado com DeviceKey.
- Pareamento físico direto concluído com a luz próxima anunciada como `Mesh Device`.
- Leitura real confirmada: luz acesa, intensidade de 20% e temperatura de 4500 K.
- Reconexão em novo processo confirmada. Controle real de brilho validado: 20% → 15% → 20%, com cada valor confirmado pela luz. A temperatura permaneceu em 4500 K.
- Ajuste físico de temperatura confirmado: 4500 K → 4600 K → 4500 K. Liga/desliga confirmado: acesa → apagada → acesa. Ambos preservaram brilho de 20%.
- Versão 0.3.3 instalada em `~/Applications/Lume.app`. O painel real foi conferido conectado, com os controles habilitados e leitura de mudanças posteriores no brilho.
- O app não redefine Bluetooth nem atualiza firmware. Só inicia um novo pareamento quando uma luz pronta é selecionada. Uma luz que guarde um vínculo antigo exige BT Reset físico feito pelo usuário.

## Abrir

Descompacte `Lume-macOS.zip` e abra `Lume.app`. Um símbolo orbital monocromático aparece na barra de menus. Clique nele para abrir o painel. No menu de opções, abra Ajustes para escolher Sistema, Claro ou Escuro e solicitar a abertura ao iniciar sessão; essa opção vem desligada.

A assinatura é local/ad-hoc, sem notarização Apple. A verificação local de assinatura não equivale à distribuição pela App Store ou aprovação de Gatekeeper em outro Mac.

## Conectar diretamente, sem celular

1. Ligue a amaran e aproxime-a do Mac.
2. Se a luz ainda guardar um vínculo antigo, use **BT Reset** na própria luz e aguarde **Success**. Isso remove o pareamento anterior. O Lume não executa esse reset.
3. No Lume, clique em **Buscar minha amaran** e selecione a sua luz marcada como **Pronta para parear**. Ela pode aparecer como `Mesh Device`.
4. Aguarde a criação da conexão e a configuração dos controles. A luz permanece com os ajustes de iluminação atuais.
5. Os controles só ficam disponíveis depois de receber o estado real da luz.

As credenciais são salvas localmente antes de enviar os dados finais de pareamento, permitindo retomar a configuração caso a conexão caia. A leitura da composição, o envio da chave de aplicação e o vínculo ao modelo de controle precisam ser confirmados pela luz. Não há dependência do aplicativo oficial.

## Importação opcional de uma configuração existente

O app precisa conhecer os dados da rede Bluetooth existente. A busca por Bluetooth não recupera essas informações.

Em **Já tenho uma configuração… → Sidus Link / arquivo…**, o importador aceita:

1. Um JSON compatível do Sidus contendo `netKeys`, `appKeys` e `nodes`, com uma rede e uma chave de aplicação. Também aceita exportações de `wesbos/amaran-BLE-control` e `neyako/amaran-hacs`.
2. Uma pasta de backup local **já existente e não criptografado** do iPhone. O importador consulta apenas os JSON de iluminação em `Documents/mesh/` dos domínios do Sidus Link/Sidus Link Pro. Outros aplicativos e arquivos pessoais não são lidos.

**Backups criptografados ainda não são suportados por este importador. Não desative a criptografia para usar o app.** Uma extração local específica e com senha pode ser preparada em uma próxima etapa, caso esse seja o caminho escolhido. A presença desses JSON varia por versão do Sidus e precisa ser confirmada no backup real.

O fluxo alternativo **Usar amaran Desktop…** lê uma configuração local do aplicativo oficial. Ele não instala nem abre o aplicativo oficial, nem importa automaticamente dados do Sidus do iPhone. Caso a luz precise ser pareada novamente no aplicativo oficial, isso exige uma decisão separada do usuário.

Depois de importar, selecione sua amaran 60x S. Ligue a luz, aproxime o Mac e conecte. A identidade da rede e as mensagens são autenticadas. Os controles só são liberados depois que a luz responde com seu estado. Se o Sidus Link estiver ocupando a conexão, pode ser necessário fechá-lo durante o teste.

## Interface glass

O painel espacial reúne liga/desliga, intensidade e temperatura em dois módulos de vidro com escalas discretas. Usa Liquid Glass nativo no macOS 26 ou posterior e material translúcido nas versões anteriores. Respeita Reduzir Transparência e Aumentar Contraste. Os ícones de interface são Phosphor; o ícone glass do aplicativo é separado do símbolo monocromático da barra de menus. Ajustes rápidos, conexão e preferências ficam no menu de opções.

Com a luz conectada e o emissor aceso, um gradiente ambiente aparece atrás dos controles e acompanha a temperatura confirmada: âmbar nas temperaturas quentes e azul suave nas frias. Ele desaparece quando o emissor apaga ou a conexão cai. A decoração fica oculta com Reduzir Transparência ou Aumentar Contraste, e a transição respeita Reduzir Movimento.

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

O app não transmite dados pela internet. O link de ajuda apenas abre o site oficial quando clicado.

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

Os estados `connected`, `setup`, `offline`, `pending` e `error` geram imagens com dados ilustrativos e encerram o processo. O renderizador é uma prévia de layout e pode não capturar fielmente o vidro e a vibrância do compositor do macOS. As imagens `docs/preview-light.png` e `docs/preview-dark.png` mostram o painel nativo.

## Licença

[MIT](LICENSE), copyright 2026 Jonatas Faria. Os avisos de código de terceiros são preservados em [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) e incluídos no aplicativo. As credenciais e os relatórios locais de Bluetooth não fazem parte do repositório.

## Fontes

- https://github.com/wesbos/amaran-BLE-control — codificação Telink e referência de transporte (MIT).
- https://github.com/neyako/amaran-hacs — beacon autenticado, filtro de proxy, isolamento dos endereços e leitura de estado (MIT).
- https://github.com/aarondfrancis/amaran/blob/main/scripts/sidus-backup-import — referência de localização e formato dos JSON do Sidus em backups iOS; implementação do importador feita em Swift neste projeto.
- https://help.amarancreators.com/en/amaran-60xs/controls — limites documentados da 60x S.
- https://www.bluetooth.com/blog/provisioning-a-bluetooth-mesh-network-part-2/ — etapas de autenticação e distribuição dos dados de pareamento PB-GATT.

Os avisos das implementações MIT estão em THIRD_PARTY_NOTICES.md e dentro do app. O motor REA não foi utilizado: esta etapa trabalha com código-fonte público já disponível, não com decompilação de um aplicativo proprietário.
