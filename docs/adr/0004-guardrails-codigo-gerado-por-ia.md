# ADR 0004 — Guardrails automáticos para código gerado por IA

**Status:** aceita

## Contexto

O app foi escrito com ajuda intensa de IA, por uma pessoa só, com prazo curto. Um estudo
comparativo em Python e Java encontrou perfis de defeito distintos e mais vulnerabilidades de
alto risco em amostras geradas por IA, mas isso não permite concluir que todo PR com IA tenha
mais defeitos que um PR humano ([Cotroneo et al., 2025](https://doi.org/10.1109/ISSRE66568.2025.00035)).
Modelos também podem inventar nomes de pacotes inexistentes; se um atacante registra um desses
nomes com código malicioso, a técnica é chamada *slopsquatting*
([Spracklen et al., USENIX Security 2025](https://www.usenix.org/system/files/usenixsecurity25-spracklen.pdf)).
Por isso, as verificações também precisam proteger suas próprias regras contra mudanças que apenas
silenciem uma falha. Revisão humana sozinha não escala para o volume de código gerado.

## Decisão

- **Guardrails antes do código:** o primeiro commit contém só as verificações; o app entra por PR.
- **Verificações determinísticas em camadas:** hooks do Claude Code e hook `Stop` do Codex → hooks
  do git → CI → regras da `main` no GitHub. No Codex, o hook `Stop` executa políticas locais e SwiftLint;
  não há bloqueio preventivo de edições ou comandos. Instruções em `AGENTS.md` orientam, mas não
  são a garantia.
- **Os guardrails se protegem:** hooks do Claude Code bloqueiam edições de arquivos de guardrail;
  mudanças neles exigem label humano (CI), e só uma pessoa faz o merge. No Codex, não há bloqueio
  preventivo de edições; as mudanças continuam sujeitas às verificações locais e do CI.
- **Exceções explícitas:** supressões e remoção de testes não são proibidas, mas exigem decisão
  humana registrada (label + justificativa no PR).
- **Cadeia de suprimentos fechada:** lista de dependências permitidas, versões exatas, actions por
  SHA, ferramentas com checksum.

## Alternativas

- **Só revisão humana:** não escala e falha justamente no que é chato de revisar (lock files,
  workflows, testes).
- **Só instruções no prompt/AGENTS.md:** a IA às vezes ignora; não há como auditar.
- **Ferramentas comerciais de revisão por IA como gate:** úteis como segunda opinião, mas são
  probabilísticas; não substituem verificações determinísticas.

## Consequências

- Mais atrito para mudanças nos guardrails (de propósito).
- No Codex, edições e comandos deixaram de ser interceptados antes da execução; as verificações preventivas
  restantes são os hooks do git e o CI. O hook `Stop` mantém a validação local ao encerrar.
- CI mais lento (runners macOS); mitigado com jobs pulados quando não se aplicam e cancelamento
  de execuções antigas.
- Deixa documentado, e verificável, como a IA foi usada com responsabilidade no projeto.
