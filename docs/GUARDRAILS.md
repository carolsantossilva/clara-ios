# Guardrails para código gerado por IA

Grande parte deste repositório foi escrita com ajuda de IA. Em vez de confiar no texto gerado,
o repositório trata todo código como **não confiável até passar por verificações automáticas**
que a IA não consegue desligar. Os guardrails vieram **antes** do código do app: o primeiro
commit tem só eles, e o app entrou por PR, passando por todas as barreiras.

## Por quê

- Instruções para a IA ("rode os testes", "escreva código seguro") são pedidos, não garantias.
- Um estudo comparativo de 2025, com mais de 500 mil amostras em Python e Java, encontrou perfis
  de defeito distintos e mais vulnerabilidades de alto risco em amostras geradas por IA. O resultado
  é limitado às linguagens, modelos e métricas estudados; não permite afirmar que todo PR com IA
  tenha mais defeitos que um PR humano ([Cotroneo et al., 2025](https://doi.org/10.1109/ISSRE66568.2025.00035)).
- Riscos de código gerado incluem dependências inexistentes inventadas pelo modelo. Se alguém
  registrar esses nomes em um repositório de pacotes com código malicioso, isso é *slopsquatting*
  ([Spracklen et al., USENIX Security 2025](https://www.usenix.org/system/files/usenixsecurity25-spracklen.pdf));
  outros riscos incluem testes que não verificam comportamento e "consertar" uma verificação desligando
  a regra.

## As camadas

| # | Camada | Onde | O que faz | Força |
|---|---|---|---|---|
| 1 | Instruções | `AGENTS.md`, `CLAUDE.md` | Arquitetura, regras do produto, como trabalhar, o que nunca fazer | Orienta |
| 2 | Hooks de agente | `.claude/settings.json`, `.codex/hooks.json`, `scripts/agent-hooks/guard.py` | Claude Code bloqueia edições de guardrails e comandos que contornam verificações, e pede confirmação para supressões; o Codex executa políticas locais e SwiftLint ao encerrar | Bloqueia ou valida a IA local |
| 3 | Hooks do git | `scripts/git-hooks/pre-commit` | Segredos (gitleaks), políticas, SwiftLint nos arquivos do commit, sem commit na `main` | Bloqueia qualquer commit local |
| 4 | CI | `.github/workflows/` | Título do PR no formato Conventional Commits, políticas, segredos no histórico, revisão de dependências, lint, compilação tratando warnings como erros, testes unitários/snapshot/UI, cobertura mínima, fluxos Maestro, CodeQL | Bloqueia o merge |
| 5 | GitHub | Regras da `main`, configurações | PR obrigatório, "CI OK", sem alertas CodeQL de severidade alta ou crítica e sem force push; varredura de segredos e proteção contra push dependem da configuração do repositório; Dependabot | Ninguém contorna sem querer |
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
confiável. Uma verificação obrigatória apenas pelo nome não garante sua origem. Esta
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
- Para mudar um guardrail de propósito, uma pessoa deve decidir e revisar. No Claude Code, inicie
  o processo com `CLARA_GUARDRAILS_UNLOCK=1 claude` para liberar a edição local. O Codex não tem
  bloqueio preventivo de edição; mudanças em caminhos protegidos ainda exigem o label
  `guardrails-change` no PR.

### Usando Codex

Codex lê `AGENTS.md` diretamente. O hook local em `.codex/hooks.json` só roda quando o
projeto é confiável; hooks que não são gerenciados precisam ser revisados e aceitos. Neste
projeto, o Codex mantém apenas o hook `Stop`, que executa as políticas locais e o SwiftLint antes de encerrar.
Para revisar e aceitar o hook, rode `codex` e abra `/hooks`. Mudanças nas definições exigem nova
revisão. Consulte a documentação oficial de [hooks do Codex](https://developers.openai.com/codex/hooks).

Diferenças em relação ao Claude Code:

- Este projeto não configura `PreToolUse` no Codex: edições e comandos não passam pelo
  `guard.py` antes da execução. O hook de `Stop` não substitui essa checagem preventiva.
- Perfis de permissão do Codex podem negar leitura de arquivos por caminho ou padrão; por
  exemplo, um perfil pode bloquear `.env`. Consulte a referência oficial de
  [configuração](https://developers.openai.com/codex/config-reference/). O hook Git e as
  verificações de segredos no CI são controles separados: quando instalado, o pre-commit
  verifica o conteúdo preparado antes do commit, enquanto o CI verifica o histórico após o
  push. Nenhum deles controla o que o Codex pode ler no workspace, e o CI só pode detectar um
  segredo depois que ele chega ao repositório. A varredura de segredos e a proteção contra push
  do GitHub são controles separados, disponíveis conforme a configuração do repositório.

## Limites conhecidos (honestidade)

- Os hooks do Claude Code usam heurísticas (expressões regulares). Pegam casos comuns, não um
  agente decidido a burlar. O Codex não tem hook preventivo de ferramenta neste projeto. A
  barreira definitiva é o CI + regras da `main`.
- Como o repositório tem uma pessoa só, não dá para exigir aprovação de outra pessoa no PR
  (o GitHub não deixa aprovar o próprio PR). A segurança fica nas verificações obrigatórias e na leitura
  do diff, registrada no template de PR.
- Cobertura e mutação medem testes, não corretude. O limite de cobertura começa conservador e só sobe.
- O Muter não tem release desde 2023; o job de mutação é experimental e não bloqueia PRs.
- Imagens de snapshot podem variar entre Intel (VM local) e Apple Silicon (CI); o CI fixa o mesmo
  Xcode da VM e os testes usam tolerância de precisão.
