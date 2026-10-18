# ADR 0002 — Uma arquitetura de apresentação por feature, escolhida pelo problema

**Status:** aceita

## Contexto

Escolher a arquitetura certa é uma questão de trade-offs. Em apps grandes é comum conviverem padrões diferentes (código antigo em MVC/VIP, novo em SwiftUI). As três telas do Clara têm necessidades diferentes.

## Decisão

| Feature | Padrão | Por quê |
|---|---|---|
| Hoje | SwiftUI + **MVVM-C** | Várias sheets e fluxos (criar, pausar, sugestões com IA, privacidade). O Coordinator tira a navegação do ViewModel, que fica testável com um router espião. |
| Registros | UIKit View Code + **VIP** | Lista com edição e exclusão, regras de concorrência (conflito de revisão) e formatação. O VIP separa regra (Interactor), formatação (Presenter) e UI (ViewController), e cada parte é testada isolada. Também representa a parte "legada" em UIKit que convive com SwiftUI. |
| Consulta | SwiftUI + **MVVM** sem coordinator | Tela única, sem navegação. Um coordinator aqui seria cerimônia sem ganho. |

## Trade-offs

- **VIP:** mais arquivos e protocolos por tela (boilerplate), mas fronteiras muito claras, bom para times grandes e telas com muita regra.
- **MVVM-C:** menos cerimônia que VIP/VIPER; o risco é o ViewModel crescer demais — mitigado com ViewModels menores por sheet (`StepSuggestionsViewModel`).
- **VIPER:** acrescentaria Entity e um Router mais formal; para estas telas, o ganho sobre VIP não compensaria.
- **MVC:** adequado para telas pequenas, mas tende a concentrar tudo na ViewController (o "Massive View Controller").

## Consequências

Quem entra no time precisa conhecer mais de um padrão. A regra é: o padrão vive dentro da feature, e a fronteira pública de toda feature é a mesma (um *builder* que recebe dependências e devolve uma tela).
