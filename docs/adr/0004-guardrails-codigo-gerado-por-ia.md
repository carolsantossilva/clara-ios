# ADR 0004 — Guardrails automáticos para código gerado por IA

**Status:** aceita

## Contexto

O app foi escrito com ajuda intensa de IA, por uma pessoa só, com prazo curto. Código gerado
por IA tende a ter mais problemas (inclusive de segurança), pode sugerir dependências
inexistentes e, diante de um check falhando, costuma "resolver" afrouxando a regra.
Revisão humana sozinha não escala para o volume de código gerado.

## Decisão

- **Guardrails antes do código:** o primeiro commit contém só as verificações; o app entra por PR.
- **Verificações determinísticas em camadas:** hooks do Claude Code → hooks do git → CI → regras
  da `main` no GitHub. Instruções em `AGENTS.md` orientam, mas não são a garantia.
- **Os guardrails se protegem:** a IA não edita arquivos de guardrail (hook), mudanças neles exigem
  label humano (CI), e só uma pessoa faz o merge.
- **Exceções explícitas:** supressões e remoção de testes não são proibidas, mas exigem decisão
  humana registrada (label + justificativa no PR).
- **Cadeia de suprimentos fechada:** lista de dependências permitidas, versões exatas, actions por
  SHA, ferramentas com checksum.

## Alternativas

- **Só revisão humana:** não escala e falha justamente no que é chato de revisar (lock files,
  workflows, testes).
- **Só instruções no prompt/AGENTS.md:** a IA às vezes ignora; não há como auditar.
- **Ferramentas comerciais de revisão por IA como gate:** úteis como segunda opinião, mas são
  probabilísticas; não substituem checks determinísticos.

## Consequências

- Mais atrito para mudanças nos guardrails (de propósito).
- CI mais lento (runners macOS); mitigado com jobs pulados quando não se aplicam e cancelamento
  de execuções antigas.
- Deixa documentado, e verificável, como a IA foi usada com responsabilidade no projeto.
