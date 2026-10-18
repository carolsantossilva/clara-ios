# ADR 0003 — IA generativa no aparelho, com substituto e sem interpretação clínica

**Status:** aceita

## Contexto

Começar uma tarefa é a parte difícil para quem usa o Clara. A proposta original do produto deixava "IA para decompor tarefas" para depois por dois motivos: privacidade (tarefas podem conter informação de saúde) e o risco de o app parecer dar conselho clínico.

## Decisão

- Sugerir **2 a 4 passos pequenos** para a tarefa em foco, **só quando a usuária pede**. Ela escolhe um passo, que vira o "próximo passo", ou fecha sem escolher.
- Provedor principal: **Foundation Models** (iOS 26), modelo da Apple **no aparelho**. Usa `@Generable` (guided generation) para receber a resposta já como struct, sem interpretar texto livre.
- Substituto: `HeuristicStepSuggester` com **NaturalLanguage** (também no aparelho), usado quando o modelo não está disponível, falha ou passa de 8 segundos (`FallbackStepSuggester` + `withTimeout`).
- A tela informa a origem da sugestão (transparência).
- **Não** fazemos análise de sentimento dos registros. Daria para fazer com NaturalLanguage, mas seria "interpretação automática de humor", explicitamente fora do escopo do produto.

## Alternativas

- **LLM em nuvem (API):** respostas melhores e funciona em qualquer aparelho, mas o texto sairia do aparelho, exigiria consentimento explícito e um backend para não embutir a chave de API no app. Fica possível no futuro como mais um provedor atrás do mesmo protocolo `StepSuggesting`.
- **Core ML com modelo próprio:** controle total, mas exige dataset, treino e manutenção do modelo, sem ganho claro para esta tarefa.

## Consequências

- Em aparelhos sem Apple Intelligence, a experiência é mais simples, mas nunca quebra.
- Trocar ou acrescentar provedores não muda a feature (Open/Closed + Dependency Inversion).
