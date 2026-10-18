@AGENTS.md

## Específico do Claude Code

- Os hooks em `.claude/settings.json` bloqueiam edição de arquivos de guardrail, comandos que
  contornam verificações e pedem confirmação quando uma edição adiciona supressões. Se um hook
  bloquear algo, não tente outro caminho para fazer a mesma coisa: explique à pessoa.
- O hook de Stop roda as políticas e o SwiftLint quando você termina. Se ele apontar falhas,
  corrija antes de encerrar.
- Este projeto costuma ser editado no Linux e compilado numa VM macOS (`ssh tahoe`). Sem
  compilar lá, não afirme que o código compila.
