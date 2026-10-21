# Instruções para agentes de IA

Este arquivo vale para qualquer agente de código (Claude Code, Codex, Copilot, Cursor...).
O `CLAUDE.md` importa este arquivo.

Estas instruções orientam, mas não garantem nada sozinhas. O que garante são as verificações
automáticas descritas em [docs/GUARDRAILS.md](docs/GUARDRAILS.md): hooks, CI e as regras da
branch `main`. Trabalhe a favor delas, nunca contra.

## O projeto

Clara é um app iOS nativo (Swift, iOS 17+) que ajuda a escolher um próximo passo, guardar
distrações e reunir registros pessoais para uma consulta. Projeto gerado com XcodeGen
(`project.yml`); o código fica num pacote SPM local, `Packages/ClaraKit`, com um target por módulo.

- `ClaraCore` não depende de nada. As features (`ClaraUI`) **nunca importam umas às outras**.
- Dependências concretas só são montadas no app (`App/AppEnvironment.swift`, o composition root).
- As três abas usam SwiftUI + MVVM.
  Siga o padrão da feature que você está mexendo (ver `docs/adr/0002`).
- Swift 6 toolchain, modo de linguagem 5 com concorrência estrita: ViewModels são `@MainActor`,
  estado compartilhado mutável fica em `actor`.

## Regras do produto (não negociáveis)

- Dados da usuária ficam **só no aparelho**. Nada de backend, nuvem ou envio de texto escrito por ela.
- Analytics é opt-in e só usa eventos do catálogo (`ClaraEvent`), **sem texto livre**.
- **Nenhuma interpretação clínica** nem análise de humor/sentimento.
- IA só no aparelho (Foundation Models), sempre com fallback e mostrando a origem da sugestão.

## Como trabalhar

1. **Teste primeiro.** Para mudança de comportamento, escreva o teste que falha, depois o código.
   Use Swift Testing e os dublês de `ClaraTestSupport` (`ImmediateClock`, `SteppingNow`...).
   Nada de `sleep`, rede real ou data/hora real em teste.
2. **Mudanças pequenas.** Um PR = um assunto. Se a mudança cresceu, divida.
3. **Rode as verificações antes de dizer que terminou** (o hook de Stop roda parte delas):
   ```bash
   ./scripts/validate.sh
   ```
   O script roda os testes dos verificadores e as políticas locais. Quando existir app ou
   pacote Swift, também exige SwiftLint e testes no simulador iOS em um Mac com Xcode.
   O simulador é selecionado automaticamente; para escolher outro, use
   `DESTINATION='platform=iOS Simulator,name=iPhone 17' ./scripts/validate.sh`.
4. **Nunca diga que algo funciona sem ter rodado.** Se não deu para compilar ou testar, diga isso
   explicitamente.

## Quando uma verificação falha

Corrija o código. **Não** enfraqueça a verificação. Isso inclui:

- apagar, desativar (`.disabled`, `XCTSkip`) ou afrouxar um teste;
- regravar referência de snapshot para "aceitar" a mudança;
- adicionar `swiftlint:disable`, `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency` ou `try!`;
- baixar o limite de cobertura ou mexer em qualquer arquivo listado em
  `guardrails/protected-paths.txt`.

Se você acha que a regra está errada, **pare e explique à pessoa**. Ela decide. Os hooks bloqueiam
essas edições e o CI recusa PRs com elas sem um label de exceção dado por uma pessoa.

## Dependências

Não adicione dependência externa por conta própria. Se uma for realmente necessária, proponha:
nome, URL, por que a biblioteca padrão não basta, mantenedor e última release. Confira que o
pacote existe e é o original (nomes parecidos são um vetor de ataque). Uma pessoa adiciona em
`guardrails/allowed-dependencies.txt`. Versões sempre exatas (`exact:`).

## Git

- Nunca commite na `main`; crie uma branch (`feat/…`, `fix/…`, `chore/…`).
- Commits and PR titles follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):
  `<type>(<optional scope>): <description>`, imperative mood, lowercase description.
  - Types: `feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `build`, `ci`, `chore`, `style`, `revert`.
  - Scopes: `today`, `records`, `consultation`, `app`, `core`, `storage`, `networking`,
    `services`, `ai`, `design-system`, `guardrails`.
  - Example: `feat(consultation): add period filter`. A breaking change adds `!` before the colon.
  - Merges are squash-only, so the PR title becomes the commit on `main`; CI checks it.
- Nunca use `--no-verify`, force push, nem mexa em labels, rulesets ou configurações do GitHub.
- Abrir PR é permitido; **merge é sempre humano**.

## PR instructions

- Before creating or editing a PR description, read `.github/pull_request_template.md`
  and use it as the structure. Preserve every section and checklist item, including when
  updating an existing PR.
- Fill in the change, verification, code origin and exceptions with evidence from the
  actual diff and checks. State when an item is not applicable or has not been verified.
- Check a box only when its full statement is supported. Never attest on a person's
  behalf that they read or approved the diff; leave those statements for the person.
