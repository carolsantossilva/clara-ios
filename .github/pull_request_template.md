## O que muda e por quê

<!-- Uma ou duas frases. Link para issue/ADR se houver. -->

## Como foi verificado

<!-- Testes novos/alterados, passos manuais, prints de antes/depois para mudanças de UI. -->

## Origem do código

- [ ] Escrito por pessoa
- [ ] Gerado ou editado por IA (ferramenta: ______ ) — e **li o diff inteiro** antes de abrir o PR

## Checklist

- [ ] Toda mudança de comportamento tem teste, e o teste falha sem a mudança
- [ ] Nenhum teste foi removido, desativado ou teve a referência de snapshot regravada sem explicação aqui
- [ ] Nenhuma supressão nova (`swiftlint:disable`, `@unchecked Sendable`, `try!`...) — ou está justificada abaixo
- [ ] Nenhuma dependência nova — ou foi conferida (existe, é o pacote certo, mantida) e adicionada em `guardrails/allowed-dependencies.txt`
- [ ] Regras do produto mantidas: dados só no aparelho, analytics sem texto da usuária, nenhuma interpretação clínica
- [ ] Acessibilidade: VoiceOver e Dynamic Type conferidos em telas novas

## Exceções

<!-- Se o PR precisar dos labels guardrail-exception ou guardrails-change, explique aqui o motivo. -->
