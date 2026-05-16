# CLAUDE.md — IARA Chat Greenfield (Fitness UNIC)

> **Audiência:** Claude Code, qualquer agente que vá executar tarefas neste projeto.
> **Versão:** v1.0 — 16/mai/2026
> **Owner:** Juliano Bortolato

---

## O que é este projeto

Chatbot de vendas via WhatsApp para a **Fitness UNIC** (academia, sede única, Campo Grande/MS). Atende leads que chegam pelo número oficial. Qualifica, tira dúvidas, agenda Aula Experimental, transfere pra humano quando necessário.

**Vida útil estimada:** 45-90 dias. Projeto **descartável** e independente do IARA V2 (sistema paralelo de retenção, outro chat, outro repositório).

---

## Princípio-mãe — PROMPT-FIRST

**Um único LLM (Claude Sonnet 4.6) conduz a conversa, com 3 tools, sem máquina de estados, sem multi-agente, sem RAG.**

```
WhatsApp → n8n (5-7 nós) → Sonnet 4.6 com system prompt grande + 3 tools → resposta → log
                                  │
                                  ├─ tool: handoff_humano(motivo)
                                  ├─ tool: agendar_aula_experimental
                                  └─ tool: salvar_perfil(campos)
```

---

## Regras inegociáveis

### 1. Arquitetura

- **System prompt grande** (~10-15k tokens) com FAQ embutido + identidade IARA + regras de tom
- **SEM** Pinecone / pgvector / qualquer RAG — FAQ é texto no prompt
- **SEM** máquina de estados / coluna `fase_atual` — Sonnet lê histórico e entende contexto
- **SEM** extração paralela de slots (não usar LLM auxiliar)
- **SEM** regex de intenção — LLM chama tool quando faz sentido
- **SEM** features adicionais — se aparecer ideia nova, vai pro V2 (sistema separado)

### 2. Banco de dados (Supabase)

- **Schema canônico:** `leads`, `leads_perfil`, `chat_messages`, `clientes_config` (4 tabelas)
- **Sede única:** sem `tenant_id`, sem multi-tenant
- **RLS habilitado em toda tabela**, sem policy criada (anon negada por padrão, service_role bypassa) — **padrão Supabase Greenfield**
- **Toda CREATE TABLE futura** deve incluir `ALTER TABLE ... ENABLE ROW LEVEL SECURITY`
- **Persistência ANTES do envio:** salvar mensagem no banco antes de enviar via Evolution. Se Evolution falhar, retry funciona

### 3. Tom e identidade

- IARA é **consultora**, não vendedora ou garçom
- Persona, planos e tom definidos em `CONHECIMENTO_ACADEMIA_GREENFIELD.md` — fonte canônica
- FAQ está em `FAQ_PINECONE_GREENFIELD.md` — vai embutido no system prompt
- **NUNCA mencionar nome de professor** na conversa
- **NUNCA inventar dado** (preço, horário, política)
- **NUNCA conceder desconto** — transferir pra humano via tool `handoff_humano`

### 4. Handoff humano (Chatwoot reaproveitado do V19)

**Plataforma:** Chatwoot self-hosted no mesmo servidor Hostinger do n8n. Instância já existente do V19 — equipe familiarizada, integrações Evolution↔Chatwoot↔n8n já depuradas em sprints anteriores.

**Mecânica:**
- IARA chama `handoff_humano(motivo)` → n8n cria/atualiza conversa no Chatwoot via API + seta `leads.ia_ativa = FALSE`
- Atendente abre Chatwoot, responde — mensagem sai via Evolution → WhatsApp do lead
- Atendente clica "Resolver" no Chatwoot → webhook dispara → n8n seta `leads.ia_ativa = TRUE`
- `clientes_config.kill_switch = TRUE` → IARA desligada **globalmente**

**Pendência antes de plugar:** auditoria das integrações Chatwoot V19 (inboxes, webhooks, API tokens, agent bots). Identificar o que serve ao Greenfield e o que é resíduo V19. Não criar Chatwoot novo — refaz sofrimento de integração que já foi resolvido.

### 5. Tools (3, sem mais)

| Tool | Quando o LLM chama |
|---|---|
| `salvar_perfil(campos)` | Captura objetivo, restrição, frequência, etc — sem questionário ativo |
| `agendar_aula_experimental(horario_iso)` | Lead confirma agendamento — consulta Google Calendar primeiro |
| `handoff_humano(motivo)` | Desconto / cancelamento / financeiro / lead pediu humano |

---

## Stack canônica

| Camada | Tecnologia | Status |
|---|---|---|
| Canal | WhatsApp via Evolution API V2 | Instância A já existe |
| Orquestrador | n8n self-hosted (Hostinger) | Já existe |
| LLM | Claude Sonnet 4.6 | A configurar |
| Banco | Supabase PostgreSQL (projeto novo) | ✅ Criado e populado |
| Handoff | Chatwoot self-hosted (Hostinger) | Reaproveita V19 — pendente auditoria |
| Agenda | Google Calendar | Já integrado |

---

## Anti-padrões — NUNCA fazer neste projeto

| Anti-padrão | Por quê |
|---|---|
| Adicionar coluna `fase_atual`, `etapa`, `step` em alguma tabela | Vira FSM travestida — projeto é prompt-first |
| Criar tabela `embeddings` ou usar pgvector | É RAG — projeto não usa RAG |
| Criar 2º LLM "pra extrair slots" / "classificar intenção" | Sonnet 4.6 faz tudo num turno só |
| Inserir mensagem no `chat_messages` com `role` fora de (`user`, `assistant`, `system`, `tool`) | CHECK constraint vai falhar |
| Acessar Supabase com anon key | RLS bloqueia. Use service_role no n8n |
| Reescrever prompt da IARA sem revisão do owner | Tom é regra inegociável — owner valida |
| Adicionar tool sem antes documentar aqui | Tool = contrato. Não vira código sem registro |
| Trazer arquitetura ou padrão do IARA V2 pra cá | V2 é outro projeto, outra arquitetura. Não cruzar |

---

## Quando consultar o owner antes de executar

- Alteração de schema (qualquer `ALTER`, `CREATE TABLE`, `DROP`)
- Mudança em system prompt da IARA
- Adicionar / remover / alterar contrato de tool
- Trocar versão do Sonnet (de 4.6 pra outra)
- Resultado da auditoria Chatwoot V19 (definir se algum webhook/automação precisa ser desativado)

## Quando pode executar direto

- Bugfix em nó n8n (sem mudar contrato externo)
- Ajuste de retry / timeout / log
- Limpeza de dado de teste no banco
- Adicionar índice / `EXPLAIN` / otimização

---

## Documentos canônicos do projeto

| Doc | Função |
|---|---|
| `CLAUDE.md` | Este arquivo. Constituição |
| `ESTADO_ATUAL_PROJETO.md` | Snapshot do que está pronto e do que falta |
| `ARQUITETURA.md` | Fluxo n8n + contrato das 3 tools |
| `SEGURANCA.md` | Vulnerabilidades + prompt injection |
| `GLOSSARIO_DECISOES.md` | Por que prompt-first, por que sem FSM/RAG |
| `CONHECIMENTO_ACADEMIA_GREENFIELD.md` | Identidade, tom, planos IARA — fonte do system prompt |
| `FAQ_PINECONE_GREENFIELD.md` | 35 chunks de FAQ — vai embutido no prompt |
| `schema_greenfield_v1_1.sql` | Schema do banco — fonte da verdade |

---

## Regra de ouro

> Se aparecer ideia nova de funcionalidade, a resposta padrão é:
> **"Isso vai pro V2 algum dia, não no Greenfield."**

Greenfield é tático, enxuto, descartável. Disciplina aqui é virtude.
