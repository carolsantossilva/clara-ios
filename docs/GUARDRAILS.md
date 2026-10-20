# Guardrails para código gerado por IA

Grande parte deste repositório foi escrita com ajuda de IA. Em vez de confiar no texto gerado,
o repositório trata todo código como **não confiável até passar por verificações automáticas**
que a IA não consegue desligar. Os guardrails vieram **antes** do código do app: o primeiro
commit tem só eles, e o app entrou por PR, passando por todas as barreiras.

## Por quê

- Instruções para a IA ("rode os testes", "escreva código seguro") são pedidos, não garantias.
- Levantamentos de 2025–2026 encontram mais problemas, e mais problemas de segurança, em PRs
  gerados por IA do que em PRs humanos.
- Falhas típicas de código gerado: dependências que não existem (ou com nome parecido com o
  original, o *slopsquatting*), testes que cobrem o código sem verificar nada, e "consertar" um
  check desligando a regra.

## As camadas

| # | Camada | Onde | O que faz | Força |
|---|---|---|---|---|
| 1 | Instruções | `AGENTS.md`, `CLAUDE.md` | Arquitetura, regras do produto, como trabalhar, o que nunca fazer | Orienta |
| 2 | Hooks do Claude Code | `.claude/settings.json`, `.claude/hooks/guard.py` | Nega edição de guardrails e comandos que contornam checks; pede confirmação para supressões; roda políticas + SwiftLint antes de encerrar | Bloqueia a IA local |
| 3 | Hooks do git | `scripts/git-hooks/pre-commit` | Segredos (gitleaks), políticas, SwiftLint nos arquivos do commit, sem commit na `main` | Bloqueia qualquer commit local |
| 4 | CI | `.github/workflows/` | Conventional Commits PR title, políticas, segredos no histórico, revisão de dependências, lint, build com warnings como erro, testes unitários/snapshot/UI, cobertura mínima, fluxos Maestro, CodeQL | Bloqueia o merge |
| 5 | GitHub | Regras da `main`, configurações | Só entra por PR com "CI OK" verde, sem alerta CodeQL alto, sem force push; secret scanning com push protection; Dependabot | Ninguém contorna sem querer |
| 6 | Acompanhamento | Scorecard, Mutação | Nota pública de boas práticas; teste de mutação semanal no `ClaraCore` | Mede |

### Políticas (`scripts/guardrails/policy_check.py`)

| Regra | Sem label | Para liberar |
|---|---|---|
| Dependência fora de `guardrails/allowed-dependencies.txt`, ou pacote Swift sem versão exata | ❌ falha | Uma pessoa confere e edita a lista (que é protegida) |
| Mudança em arquivo de `guardrails/protected-paths.txt` | ❌ falha | Label `guardrails-change` |
| Supressão nova (`swiftlint:disable`, `@unchecked Sendable`, `try!`, teste desativado, snapshot regravado...) | ❌ falha | Label `guardrail-exception` + justificativa no PR |
| Número de testes diminuiu | ❌ falha | Label `guardrail-exception` |

No CI, alterações somente em Markdown na raiz ou em prosa/imagens raster dentro de `docs/`
podem pular Maestro. Qualquer outro caminho desconhecido mantém os fluxos. PRs executam
todos os fluxos, exceto os marcados com a tag Maestro `full`; os fluxos sem tag continuam
incluídos como smoke. A execução semanal e `workflow_dispatch` executam a suíte inteira.
Assim, um fluxo novo entra no smoke automaticamente e só sai dele quando alguém o marca
explicitamente como `full`.
Flows `full` podem falhar sem bloquear o PR e a falha pode aparecer só na validação manual de
release; rode `workflow_dispatch` antes de uma release para validar a suíte completa.

Labels são decisão humana: os hooks impedem a IA de adicioná-los.

Ao adicionar ou remover labels, o CI reavalia as políticas com os labels atuais sem
repetir os jobs macOS. O "CI OK" exige a validação do código de uma execução do mesmo
workflow, PR e commit de merge; resultados falhos, cancelados ou ainda pendentes não
servem. Labels não cancelam a execução de código em andamento. Se não houver validação
válida, reexecute a execução de código (opened/synchronize/reopened), ou aguarde seu
fim e reexecute o CI do label. Antes de aprovar o resultado, toda execução consulta
novamente os labels atuais para evitar aceitar uma exceção removida durante os testes.

### Origem confiável das políticas

O CI executa o verificador Python e lê as listas de regras da revisão base, nunca da
proposta. Os manifests e o diff da proposta são lidos como dados do Git, sem checkout,
build ou import dos arquivos propostos na avaliação de políticas. Esvaziar a lista de
proteção ou substituir o verificador no PR não muda a decisão dessa avaliação.

Isso também vale para a lista de dependências: uma nova biblioteca exige primeiro um
PR humano que aprove a lista e seja incorporado à base; só depois o PR que a utiliza.
O label `guardrails-change` autoriza a mudança protegida, mas não libera dependências
que ainda estejam fora da lista da base.

O workflow `trusted-policy.yml`, disparado por `pull_request_target`, usa somente o
código da base e token de leitura. Ele busca os objetos Git da proposta sem checkout
e consulta os labels atuais antes da avaliação. Build e testes continuam no evento
`pull_request`, fora desse contexto. Referência: [orientação de segurança do GitHub](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target).

**Limite:** o workflow comum e o nome `CI OK` ainda podem ser modificados num PR.
Para tornar a avaliação independente uma barreira obrigatória contra workflows
hostis, uma pessoa precisa configurar uma regra externa que exija o workflow
confiável. Um check obrigatório apenas pelo nome não garante sua origem. Esta
mudança não altera rulesets, labels ou configurações do GitHub.

### Cadeia de suprimentos

- Actions fixadas pelo SHA do commit (uma tag pode ser movida para código malicioso).
- Ferramentas do CI baixadas com versão fixa e checksum (`scripts/ci/install-tools.sh`).
- `GITHUB_TOKEN` só com leitura; checkout sem guardar credenciais; `harden-runner` audita a rede nos jobs Linux.
- Dependabot com espera de 14 dias antes de propor uma versão nova.
- Lista de dependências permitidas + versões exatas.

## Como usar no dia a dia

```bash
scripts/install-git-hooks.sh       # uma vez por clone
brew install gitleaks swiftlint    # macOS
```

- Trabalhe numa branch e abra PR. O merge é sempre seu.
- Para mudar um guardrail de propósito: edite você mesma, ou inicie o Claude Code com
  `CLARA_GUARDRAILS_UNLOCK=1 claude`. O PR vai precisar do label `guardrails-change`.

## Limites conhecidos (honestidade)

- Os hooks do Claude Code usam heurísticas (expressões regulares). Pegam o caso comum, não um
  agente decidido a burlar. A barreira definitiva é o CI + regras da `main`.
- Como o repositório tem uma pessoa só, não dá para exigir aprovação de outra pessoa no PR
  (o GitHub não deixa aprovar o próprio PR). A segurança fica nos checks obrigatórios e na leitura
  do diff, registrada no template de PR.
- Cobertura e mutação medem testes, não corretude. O limite de cobertura começa conservador e só sobe.
- O Muter não tem release desde 2023; o job de mutação é experimental e não bloqueia PRs.
- Imagens de snapshot podem variar entre Intel (VM local) e Apple Silicon (CI); o CI fixa o mesmo
  Xcode da VM e os testes usam tolerância de precisão.
