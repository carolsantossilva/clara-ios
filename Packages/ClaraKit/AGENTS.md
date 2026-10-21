# Instruções para agentes: ClaraKit

Estas regras complementam o `AGENTS.md` da raiz e se aplicam a `Packages/ClaraKit`.

## Organização Swift

- Separe tipos independentes em arquivos com o nome do tipo. Um tipo principal por arquivo é uma convenção comum, não uma regra da linguagem Swift.
- Mantenha tipos aninhados e extensões diretamente ligadas junto do tipo principal. Agrupe tipos pequenos quando formarem uma família coesa; separe conceitos e suítes de teste sem relação direta.
- Use `// MARK: -` para separar blocos com responsabilidades distintas em tipos maiores; evite marcadores artificiais em tipos pequenos.
- Mantenha helpers de teste junto da suíte que os usa; extraia-os quando forem compartilhados.
- As [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) tratam do desenho de APIs, não impõem organização de arquivos. Para esta convenção, consulte [Google Swift Style](https://google.github.io/swift/#source-file-basics) e [Swift Protobuf](https://github.com/apple/swift-protobuf/blob/main/Documentation/STYLE_GUIDELINES.md#file-organization).

## I/O e persistência

- Injete dependências externas por uma interface pequena que exponha só a operação usada. Mantenha o adaptador de produção como padrão e monte implementações concretas no composition root. Use doubles determinísticos nos testes; não faça rede real.
- Os registros da usuária permanecem no aparelho. Não os envie a serviços, analytics ou sincronização em nuvem.
- `Application Support` participa de backups do iOS. Para arquivos que não devem entrar no backup, reaplique `isExcludedFromBackup` após cada gravação, pois operações atômicas podem redefinir a propriedade. A Apple descreve isso como orientação ao sistema, não como garantia absoluta ([file system](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively), [iCloud Backup](https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup)). Cubra em testes a gravação, a substituição atômica e a reabertura.

## Requisições e edição

- Repita automaticamente apenas operações seguras ou idempotentes. No cliente atual, limite retries a `GET`; só permita retry de `POST` com garantia explícita de idempotência, como uma chave aceita pelo servidor ([RFC 9110, §9.2.2](https://www.rfc-editor.org/rfc/rfc9110.html#section-9.2.2)). Teste a quantidade de requisições em sucesso após retry e quando o retry deve ser recusado.
- Ao aplicar um draft, propague todos os campos que ele representa e preserve invariantes relacionados, como data e fuso horário ao mudar o tipo do registro. Teste os campos alterados e confirme que propriedades não editadas, como revisão e data de atualização, são preservadas.

## Datas e calendários

- Trate componentes e resultados de `Calendar` como opcionais. Propague falhas com `init?`, `guard let` ou um resultado explícito; não substitua componentes ausentes por zero nem invente uma data.
- Ao converter texto ou somar componentes, valide o resultado antes de usá-lo. Propague falhas do calendário com `nil` ou erro; não substitua componentes ausentes por zero nem invente um valor de retorno, como devolver o dia original.

## Testes que dependem de tempo

- Use datas fixas para valores sem dependência temporal. Quando o comportamento depender da passagem do tempo, injete `Clock`; use `ImmediateClock` ou `SteppingNow` de `ClaraTestSupport` ([API `Clock`](https://developer.apple.com/documentation/swift/clock)).
- Injete `ImmediateClock` nos testes de retry para o backoff não esperar tempo real. Não use `.now`, `Date()`, `Task.sleep` ou esperas em tempo real em testes determinísticos.
- Para timeout, controle o relógio e faça a operação de teste responder ao cancelamento. Prefira Swift Testing e doubles de `ClaraTestSupport`; não use rede, armazenamento compartilhado ou relógio reais.
