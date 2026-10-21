# Revisão ponytail do ClaraKit

Escopo: Packages/ClaraKit. A revisão identificou os problemas abaixo e aplicou as soluções descritas.

## 1. Tipos independentes no mesmo arquivo

**Problema**

Models.swift reunia modelos independentes, LocalRepositories.swift tinha três implementações diferentes e ReportBuilderTests.swift misturava quatro suítes sem relação direta. Isso dificulta localizar e alterar um conceito sem percorrer outros.

**Padrão de mercado**

A convenção de um tipo principal por arquivo não é uma regra da linguagem. As [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) tratam do desenho das APIs, não da organização dos arquivos. Guias de projeto recomendam nomear o arquivo pela entidade principal e permitem agrupar tipos pequenos e relacionados: [Google Swift Style Guide](https://google.github.io/swift/#source-file-basics) e [Swift Protobuf Style Guidelines](https://github.com/apple/swift-protobuf/blob/main/Documentation/STYLE_GUIDELINES.md#file-organization).

**Solução**

Os modelos independentes agora têm arquivos próprios (`Distraction.swift`, `FocusTask.swift`, `LocalDay.swift`, `Mood.swift`, `Moment.swift` e `MomentDraft.swift`); a extensão de `String` foi movida para `String+Trimming.swift`, e cada repositório local também tem arquivo próprio. As suítes independentes de Core foram separadas em `ReportBuilderTests.swift`, `LocalDayTests.swift`, `MomentDraftTests.swift` e `TimeoutTests.swift`. Tipos aninhados e grupos pequenos e coesos, como contratos de repositório, continuam juntos para evitar fragmentação sem ganho. Os modelos ficam em `ClaraCore/Models/`; os dois arquivos do resumo ficam em `ClaraCore/Reports/`.

## 2. Dependência direta de URLSession

**Problema**

URLSessionHTTPClient recebia a classe concreta URLSession. Isso acoplava a implementação à API de transporte e exigia configurar uma sessão real para substituir esse limite em testes.

**Padrão de mercado**

Uma interface pequena no limite de I/O permite trocar o adaptador concreto por um dublê nos testes. O protocolo descreve apenas a operação que o cliente realmente usa.

**Solução**

Foi criado `URLSessionProtocol` com `data(for:)`; `URLSession` o implementa e continua sendo o valor padrão (`URLSession.shared`). O cliente recebe qualquer implementação do protocolo. Um teste usa um actor fake; os testes com `URLProtocol` continuam verificando a integração com uma `URLSession` configurada para interceptar requisições.

## 3. Registros locais incluídos em backups

**Problema**

clara.json fica em Application Support, que o iOS inclui em backups por padrão. Assim, um backup do iCloud poderia levar registros pessoais para fora do aparelho, contrariando a regra local-only do Clara.

**Padrão de mercado**

A Apple documenta que Application Support participa de backups e oferece isExcludedFromBackup para excluí-lo: [Using the file system effectively](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively) e [Optimizing your app’s data for iCloud Backup](https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup). A Apple também esclarece que essa propriedade orienta o sistema, mas não garante sozinha que o arquivo nunca será incluído em um backup.

**Solução**

LocalDatabase agora reaplica a exclusão depois de cada gravação atômica e ao abrir um arquivo existente. O teste de persistência limpa a propriedade, grava de novo e verifica que foi reaplicada; também cobre a correção ao reabrir um arquivo.

## 4. Retry automático de POST

**Problema**

O cliente repetia qualquer método ao receber um erro transitório. Se um servidor processasse um POST, mas a resposta se perdesse, a repetição poderia criar o mesmo recurso duas vezes.

**Padrão de mercado**

A seção 9.2.2 da [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html#section-9.2.2) define idempotência e recomenda não repetir automaticamente métodos não idempotentes sem evidência de que a repetição é segura.

**Solução**

Como os métodos suportados hoje são `GET` e `POST`, o retry automático só acontece em `GET`. Um teste envia um `POST` que recebe 503 e verifica que houve uma única requisição. Um futuro `POST` só deve ganhar retry se houver uma garantia explícita de idempotência.

## 5. Edição descartava a mudança de tipo do registro

**Problema**

MomentDraft(editing:) copiava kind, mas Moment.applying(_:) ignorava esse campo. Ao editar um registro e mudar de check-in para evento, a alteração era perdida; se a data do evento também mudasse, ela não era aplicada.

**Padrão de mercado**

Uma operação que aplica um rascunho de edição precisa propagar os campos editáveis que esse rascunho representa e manter os invariantes relacionados.

**Solução**

applying(_:) agora aplica draft.kind e considera o tipo resultante ao decidir se atualiza data e fuso. O teste cobre a conversão para evento, a data/fuso novos e a preservação de revisão e data de atualização.

## 6. Testes dependiam de tempo real

**Problema**

O teste de `withTimeout` usava `Task.sleep` e dependia do tempo real do relógio do sistema. Testes de retry também configuravam backoff de 1 ms que esperava de verdade; alguns testes de repositório usavam o `now` padrão baseado em `.now`, e o teste de `MomentDraft` inicializava um draft com `.now`. Isso introduzia esperas e datas reais em testes, contra a regra do projeto.

**Padrão de mercado**

Swift oferece o protocolo `Clock`; este projeto já tinha `ImmediateClock` em `ClaraTestSupport` para avançar o tempo lógico sem esperar ([documentação de `Clock`](https://developer.apple.com/documentation/swift/clock)).

**Solução**

A assinatura pública existente de `withTimeout` continua usando `ContinuousClock`; um overload aceita um `Clock`. O teste usa `OperationWinsClock` para provar que a operação pode vencer e `ImmediateClock` para o timeout, com uma operação que verifica cancelamento. `URLSessionHTTPClient` também recebe um `Clock` para controlar o backoff; os testes de retry usam `ImmediateClock`. Os testes de repositório agora passam uma data fixa, e o teste de `MomentDraft` usa timestamp fixo. Assim, os testes não usam `Task.sleep`, `.now` ou espera por tempo real.

## 7. Falha de conversão do calendário virava data fictícia

**Problema**

`LocalDay.init(_:in:)` substituía componentes ausentes do calendário por zero. Isso transformava uma falha de conversão em uma data sintética, sem permitir que os chamadores distinguissem a falha. `ReportBuilder` também assumia que todo registro sempre podia ser convertido em dia local.

**Padrão de mercado**

As propriedades de `DateComponents`, como `year`, são opcionais ([documentação de `DateComponents.year`](https://developer.apple.com/documentation/foundation/datecomponents/year)); `Calendar.date(from:)` e `date(byAdding:value:to:wrappingComponents:)` também podem retornar `nil` ([documentação de `Calendar.date(from:)`](https://developer.apple.com/documentation/foundation/calendar/date%28from%3A%29), [documentação de `Calendar.date(byAdding:)`](https://developer.apple.com/documentation/foundation/calendar/date%28byadding%3Avalue%3Ato%3Awrappingcomponents%3A))). Propague a falha em vez de substituí-la por um valor sentinela como zero.

**Solução**

`LocalDay.init(_:in:)` agora é failable. A leitura de ISO valida o resultado por round-trip; `adding(days:)` lança `LocalDay.AdditionError.calendarCalculationFailed` quando o calendário não consegue calcular o resultado. `ReportBuilder` ignora registros cuja data não possa ser convertida. Os testes cobrem uma data fora do intervalo conversível, a falha de soma, o avanço de ano e strings ISO inválidas.

## 8. Escopo do erro de `LocalDay.adding(days:)`

**Problema**

`AdditionError` é um tipo público e havia dúvida se deveria ficar fora de `LocalDay`.

**Padrão de mercado**

Em Swift, tipos aninhados ajudam a limitar o escopo e deixam claro quem é responsável por defini-los. Um erro exclusivo de uma operação não precisa virar um nome top-level compartilhado.

**Solução**

`LocalDay.AdditionError` permanece aninhado porque só descreve falhas de `adding(days:)`. Isso permite que o chamador use um erro tipado sem poluir o módulo com um tipo que não tem outros consumidores.

## 9. `ParkingNote` não expressava o conceito do produto

**Problema**

`ParkingNote` usava o jargão de “parking lot”, enquanto o produto fala em guardar distrações.

**Padrão de mercado**

Nomes de tipos de domínio devem seguir o vocabulário usado pelo produto e por quem mantém o código, não uma metáfora interna de implementação.

**Solução**

O modelo e seus contratos agora se chamam `Distraction`, `DistractionRepository` e `LocalDistractionRepository`. A chave JSON persistida é `distractions`.

## 10. `ClaraCore` estava plano demais

**Problema**

Todos os tipos estavam na raiz de `ClaraCore`, dificultando distinguir modelos e código do relatório.

**Padrão de mercado**

Organize arquivos em diretórios quando houver grupos coesos; evite criar uma pasta que contenha um único arquivo ou separar tipos que sempre mudam juntos.

**Solução**

Os seis value types do domínio foram agrupados em `Models/`, e `Report.swift` com `ReportHTMLRenderer.swift` em `Reports/`. `Repositories.swift`, `Timeout.swift` e `String+Trimming.swift` continuam na raiz: cada um representa uma preocupação pequena sem formar um segundo grupo de vários arquivos.

## 11. HTML multilinha em `ReportHTMLRenderer`

**Problema**

Havia dúvida se o HTML e o CSS deveriam sair do código Swift para um template separado ou uma biblioteca.

**Padrão de mercado**

As abordagens variam com a complexidade. O `WKWebView` da Apple aceita HTML criado pelo próprio app ([`loadHTMLString`](https://developer.apple.com/documentation/webkit/wkwebview/loadhtmlstring(_:baseurl:))). Leaf oferece templates para aplicações Vapor ([documentação do Leaf](https://docs.vapor.codes/leaf/getting-started/)); `swift-html` oferece uma DSL Swift tipada, mas adiciona uma dependência ([projeto `swift-html`](https://github.com/pointfreeco/swift-html#motivation)). Recursos `.html` também podem ser incluídos em um pacote Swift e lidos por `Bundle.module` ([documentação da Apple](https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package)).

**Solução**

O HTML e o CSS foram movidos para `Reports/Resources/report.html`, incluído no target SwiftPM e lido com `Bundle.module`. `ReportHTMLRenderer` mantém apenas os blocos dinâmicos e a substituição dos marcadores; o conteúdo pessoal passa por `escape`, e o teste também confirma que marcadores escritos pela usuária não são interpretados como template. `render` propaga falhas ao localizar ou ler o recurso, sem retornar um documento vazio.

## 12. `Sendable` nos contratos de Networking

**Problema**

Vários protocolos e tipos de Networking declaram `Sendable`, parecendo redundante à primeira vista.

**Padrão de mercado**

`Sendable` documenta e permite ao compilador verificar que valores podem atravessar domínios de concorrência com segurança. O Swift exige que valores enviados entre tarefas e atores sejam seguros para transferência ([documentação de `Sendable`](https://developer.apple.com/documentation/swift/sendable)).

**Solução**

As conformidades permanecem: endpoints e respostas atravessam operações assíncronas; `HTTPClient` pode ser compartilhado como dependência; `URLSessionHTTPClient` guarda a sessão em um tipo `Sendable`; `HTTPMethod` compõe endpoints e `RetryPolicy` é estado imutável durante a chamada. Não são marcadores decorativos: cada um documenta um limite de concorrência da API.

## 13. Protocolos junto da implementação em `HTTPClient.swift`

**Problema**

Contratos e implementação de rede estavam concentrados em um único arquivo, dificultando encontrar a interface que cada tipo oferece.

**Padrão de mercado**

Uma convenção comum em Swift é nomear arquivos pelo tipo principal. Tipos pequenos que formam uma extensão coesa podem ficar juntos, mas protocolos independentes não precisam dividir arquivo com um cliente concreto.

**Solução**

`Endpoint`, `HTTPClient` e `URLSessionProtocol` agora têm arquivos próprios. `URLSessionHTTPClient`, `HTTPMethod`, `APIError` e `RetryPolicy` também foram separados pelo mesmo critério, mantendo todos no diretório `Networking`.

## 14. Uso de `any URLSessionProtocol`

**Problema**

O armazenamento e os parâmetros do cliente usam `any URLSessionProtocol`, e havia dúvida sobre a necessidade da palavra `any`.

**Padrão de mercado**

`any Protocol` declara um tipo existencial: o valor pode conter qualquer implementação daquele protocolo, com a identidade concreta apagada ([documentação Swift sobre tipos existenciais](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/opaquetypes/)).

**Solução**

`any` permanece porque a sessão concreta é escolhida em runtime e armazenada no cliente: produção usa `URLSession.shared`; testes passam um fake. Remover `any` exigiria tornar `URLSessionHTTPClient` genérico e propagar o tipo da sessão para chamadores, sem benefício prático nesta API.

## 15. Retry iterativo em vez de recursão

**Problema**

O retry de `send(_:)` usa `while true`; havia dúvida se chamadas recursivas seriam mais claras.

**Padrão de mercado**

Repetições limitadas são normalmente expressas com controle iterativo. Recursão é útil quando a decomposição recursiva faz parte do problema; aqui só adicionaria novas chamadas assíncronas e um caminho de retorno menos direto.

**Solução**

O loop foi mantido. `RetryPolicy.maxAttempts` limita as tentativas, e o `catch` só captura erros retryable de `GET`; qualquer outro erro propaga para o chamador. A iteração deixa o limite e a condição de parada visíveis.

## 16. `guard` ou `defer` em `makeRequest` e `perform`

**Problema**

Havia duas validações consecutivas em cada método, e surgiu a hipótese de substituí-las por `defer`.

**Padrão de mercado**

`guard` valida uma condição e sai antecipadamente quando ela falha. `defer` agenda limpeza ou uma ação que deve ocorrer ao sair do escopo; ele não substitui validação nem transforma falhas em erros.

**Solução**

Os `guard`s permanecem: `makeRequest` valida a construção de URL em duas etapas e `perform` distingue resposta HTTP inválida de status fora de 2xx. Nenhum método possui recurso que precise de limpeza adiada, então `defer` não se aplica.

## 17. Acesso a `makeRequest`

**Problema**

`makeRequest` era internal embora só fosse usado por `URLSessionHTTPClient`.

**Padrão de mercado**

Use o menor escopo de acesso que atende aos chamadores. Não mantenha API interna aberta apenas para permitir que testes acessem um detalhe de implementação.

**Solução**

`makeRequest` agora é `private`. Os testes verificam o comportamento público através do envio e da sessão falsa, sem depender diretamente do helper.

## 18. Nome `Snapshot` no `LocalDatabase`

**Problema**

`Snapshot` podia parecer um tipo auxiliar de teste ou snapshot visual em vez do estado persistido.

**Padrão de mercado**

“Snapshot” é um nome usado para uma cópia coerente de um estado em um instante. A propriedade value-semantic pode ser editada e, depois, publicada como uma nova versão.

**Solução**

O nome permanece: `read` entrega uma cópia do conjunto de registros e `write` edita outra cópia, persistindo-a antes de publicar no actor. A docstring de `LocalDatabase.Snapshot` agora explicita que ele representa todos os registros persistidos.

## Verificação

`git diff --check` passou. `swiftlint lint --strict` passou sem violações em 33 arquivos; duas regras foram puladas porque exigem SourceKit, cujo acesso é proibido neste ambiente. `./scripts/validate.sh` passou nos 56 testes Python e nas políticas locais, mas parou na checagem de ferramentas porque este ambiente não tem `xcodebuild`; os testes Swift não foram executados. O script também avisou que o conjunto de mudanças inclui paths de guardrails e que o PR exigirá o label humano correspondente.
