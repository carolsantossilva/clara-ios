# Clara — iOS nativo

Clara ajuda a escolher um próximo passo, guardar distrações e reunir registros pessoais para levar a uma consulta. Esta é a versão **nativa em Swift** do app que comecei em React Native (`daily-focus`), reescrita como se fosse parte de um app grande: modular, testada e com CI.

> Privacidade é requisito de produto: tarefas e registros ficam **só no aparelho** (arquivo com proteção de dados do iOS). A IA roda no aparelho. Analytics é opt-in e nunca envia texto escrito pela usuária.

## Funcionalidades

| Aba | O que faz | Arquitetura |
|---|---|---|
| **Hoje** | Tarefa em foco, timer de foco (teste A/B 15/25 min), "pausar e deixar uma pista", "isso pode esperar", **sugestão de passos pequenos com IA** e aviso de feriado (BrasilAPI) | SwiftUI + **MVVM-C** |
| **Registros** | Check-in diário e momentos avulsos, editar/excluir, linha do tempo | UIKit **View Code** + **VIP** |
| **Consulta** | Escolher período e registros, prévia fiel e exportação em **PDF** | SwiftUI + **MVVM** |

## Como rodar (Mac)

```bash
brew install xcodegen swiftlint
cd clara-ios
xcodegen generate        # gera Clara.xcodeproj a partir do project.yml
open Clara.xcodeproj
```

Escolha um simulador de iPhone e rode (⌘R). Testes: ⌘U.

- **Snapshot tests:** a primeira execução grava as imagens de referência em `Packages/ClaraKit/Tests/SnapshotTests/__Snapshots__` e **falha de propósito**. Rode de novo e eles passam. Faça commit das imagens.
- **IA no aparelho:** precisa de iOS 26 + aparelho com Apple Intelligence (Mac Apple Silicon com Apple Intelligence ligado, ou iPhone 15 Pro ou mais novo). Num Mac Intel/VM, o app usa automaticamente as sugestões simples (NaturalLanguage) e mostra isso na tela.
- **Remote config:** o app lê `config/remote-config.json` direto deste repositório no GitHub. Sem rede, usa o último valor em cache ou os valores embarcados.
- Se a sua versão do XcodeGen não aceitar os testes do pacote no scheme, rode-os direto: `cd Packages/ClaraKit && xcodebuild test -scheme ClaraKit-Package -destination 'platform=iOS Simulator,name=iPhone 17'`.

Fastlane: `bundle install`, depois `bundle exec fastlane lint` ou `bundle exec fastlane test`.

Fluxos de ponta a ponta com [Maestro](https://maestro.dev), com o app instalado num simulador: `maestro test .maestro`.

## Guardrails para código gerado por IA

Este projeto foi escrito com ajuda de IA. Antes de qualquer código do app, o repositório ganhou
verificações automáticas que a IA não consegue desligar: hooks do Claude Code, hook de pre-commit,
CI com políticas, segredos, lint, testes, cobertura, Maestro e CodeQL, e regras na branch `main`.
Detalhes em [docs/GUARDRAILS.md](docs/GUARDRAILS.md).

```bash
scripts/install-git-hooks.sh   # uma vez por clone
```

## Estrutura

```
App/                      Target do app: composition root, abas, painel de privacidade, MetricKit
AppUITests/               Testes de UI (XCUITest)
Packages/ClaraKit/        Pacote SPM local com todos os módulos
  Sources/
    ClaraCore/            Modelos (structs), protocolos de repositório, resumo e HTML (puro)
    ClaraStorage/         Banco local (actor) + repositórios
    ClaraNetworking/      Cliente REST genérico (Endpoint com associatedtype, retry, erros)
    ClaraServices/        Feature flags/A-B, remote config, analytics, crash reporting, feriados
    ClaraAI/              Foundation Models (on-device) + fallback NaturalLanguage
    ClaraLegacy/          Objective-C "legado" (formatador e store com completion handler)
    ClaraDesignSystem/    Tokens (claro/escuro), tipografia com Dynamic Type, componentes
    TodayFeature/         SwiftUI + MVVM-C
    RecordsFeature/       UIKit View Code + VIP
    ConsultationFeature/  SwiftUI + MVVM, exportação PDF
    ClaraTestSupport/     Dublês compartilhados entre as suítes
  Tests/                  Swift Testing + snapshot tests
config/remote-config.json Remote config servido pelo GitHub
docs/                     Guardrails e ADRs
```

Grafo de dependências (as features não se conhecem; tudo aponta para `ClaraCore`):

```
                 App (composition root)
        ┌───────────┼──────────────┬──────────────┐
  TodayFeature  RecordsFeature  ConsultationFeature  ClaraStorage
     │  │  │         │               │                 │
     │  │  └──── ClaraDesignSystem ──┘                 │
     │  └── ClaraAI                                    │
     └──────── ClaraServices ── ClaraNetworking        │
                 │      └── ClaraLegacy (ObjC)         │
                 └──────────── ClaraCore ◀─────────────┘
```

## Documentação

- [Guardrails para código gerado por IA](docs/GUARDRAILS.md)
- Decisões de arquitetura: [modularização](docs/adr/0001-modularizacao-spm-xcodegen.md) · [uma arquitetura por feature](docs/adr/0002-arquitetura-por-feature.md) · [IA no aparelho](docs/adr/0003-ia-no-aparelho.md) · [guardrails para IA](docs/adr/0004-guardrails-codigo-gerado-por-ia.md)
