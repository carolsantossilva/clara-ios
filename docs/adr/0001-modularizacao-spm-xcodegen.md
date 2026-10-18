# ADR 0001 — Modularização com SPM local e projeto gerado por XcodeGen

**Status:** aceita

## Contexto

O app tem três features, serviços de plataforma e um design system. Em um app grande, o código de cada feature precisa compilar e ser testado isolado, o grafo de dependências precisa ser explícito e o `.xcodeproj` não pode ser fonte de conflito de merge.

## Decisão

- Um pacote SPM local (`Packages/ClaraKit`) com um target por módulo. Features dependem de `ClaraCore` (modelos + protocolos) e de serviços; **nenhuma feature depende de outra**.
- O app é o *composition root*: só ele conhece implementações concretas (banco, HTTP, IA) e as injeta.
- O `.xcodeproj` é gerado pelo XcodeGen a partir de `project.yml` e fica fora do git.
- Dublês de teste compartilhados ficam em `ClaraTestSupport`, um target comum que só os testes usam.

## Alternativas consideradas

- **CocoaPods:** em modo de manutenção, adiciona `Podfile.lock`, workspace e scripts de build. O SPM é nativo no Xcode. Num app que já usa Pods, a migração seria gradual: módulos novos em SPM e pods antigos convivendo.
- **Tuist:** mais poderoso (cache de módulos, grafo, templates). É o próximo passo natural se o número de módulos crescer; o XcodeGen foi escolhido por ser mais simples para o tamanho atual.
- **Bazel/Buck:** builds remotos e cache distribuído compensam com centenas de módulos e muitos devs; para este tamanho, o custo de manter as regras não se paga.

## Consequências

- Builds incrementais menores: mudar `RecordsFeature` não recompila `TodayFeature`.
- O compilador impede dependências proibidas (uma feature importar outra não compila).
- Custo: mais `public` e inits explícitos nas fronteiras dos módulos.
