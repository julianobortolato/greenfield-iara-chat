# IARA Chat Greenfield — Fitness UNIC

Chatbot de vendas via WhatsApp para a Fitness UNIC (Campo Grande/MS). Qualifica leads, agenda Aula Experimental e transfere para humano quando necessário.

**Vida útil estimada:** 45–90 dias. Projeto tático e independente do IARA V2.

## Arquitetura (prompt-first)

```
WhatsApp → n8n (5-7 nós) → Claude Sonnet 4.6 + 3 tools → resposta → log
```

Sem RAG, sem máquina de estados, sem multi-agente. Um único LLM conduz tudo.

## Stack

| Camada | Tecnologia |
|---|---|
| Canal | WhatsApp via Evolution API V2 |
| Orquestrador | n8n self-hosted (Hostinger) |
| LLM | Claude Sonnet 4.6 |
| Banco | Supabase PostgreSQL |
| Handoff | Chatwoot self-hosted (reaproveita V19) |
| Agenda | Google Calendar |

## Estrutura

```
docs/       documentação do projeto
sql/        schema do banco (fonte da verdade)
n8n/        exports de workflows
prompts/    versões do system prompt
```

## Documentos principais

- `CLAUDE.md` — constituição do projeto (leia antes de qualquer tarefa)
- `docs/ESTADO_ATUAL_PROJETO.md` — o que está pronto e o que falta
- `docs/ARQUITETURA.md` — fluxo n8n + contrato das 3 tools
- `sql/schema_greenfield_v1_1.sql` — schema canônico do banco
