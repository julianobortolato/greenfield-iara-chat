# ESTADO ATUAL — IARA Chat Greenfield

> **Snapshot:** 16/mai/2026
> **Versão:** v1.0
> **Owner:** Juliano Bortolato

---

## Visão de uma linha

Schema do banco pronto e canônico. Documentação base em construção. Nenhum nó n8n implementado, nenhuma tool codada, nenhum prompt da IARA escrito. Próximo bloco de trabalho é desenho técnico (ARQUITETURA.md) e depois execução pelo Claude Code.

---

## O que está PRONTO

| Item | Status | Evidência |
|---|---|---|
| Projeto Supabase Greenfield criado | ✅ | Console Supabase |
| Schema canônico (4 tabelas) | ✅ | `schema_greenfield_v1_1.sql` rodado |
| RLS habilitado em todas as 4 tabelas | ✅ | Query de verificação retornou 4/4 |
| Seed `clientes_config` (Fitness UNIC) | ✅ | 1 linha inserida |
| Trigger `updated_at` automático | ✅ | Em `leads`, `leads_perfil`, `clientes_config` |
| CLAUDE.md (constituição do projeto) | ✅ | v1.0 |
| Padrão RLS Supabase Greenfield (memória) | ✅ | Salvo permanentemente |
| Conteúdo IARA (identidade, tom, FAQ) | ✅ | `CONHECIMENTO_ACADEMIA_GREENFIELD.md` + `FAQ_PINECONE_GREENFIELD.md` |

---

## O que está DECIDIDO mas não executado

| Decisão | Implementação |
|---|---|
| Stack inteira (Evolution + n8n + Sonnet 4.6 + Supabase + Chatwoot + Calendar) | Briefing congelado |
| Arquitetura prompt-first (1 LLM + 3 tools, sem FSM, sem RAG) | Briefing congelado |
| Modelo único Sonnet 4.6 (sem multi-modelo) | Decidido neste chat |
| Handoff via Chatwoot V19 reaproveitado | Decidido neste chat |
| 3 tools: `salvar_perfil`, `agendar_aula_experimental`, `handoff_humano` | Briefing congelado — contratos a documentar em ARQUITETURA.md |

---

## O que FALTA — ordem de execução

### Bloco 1 — Documentação canônica (em curso)

| # | Doc | Status |
|---|---|---|
| 1 | `CLAUDE.md` | ✅ |
| 2 | `ESTADO_ATUAL_PROJETO.md` | ✅ este aqui |
| 3 | `ARQUITETURA.md` (fluxo n8n + contratos tools) | ⏳ próximo |
| 4 | `SEGURANCA.md` (vulnerabilidades + injection) | ⏳ |
| 5 | `GLOSSARIO_DECISOES.md` (por que prompt-first, etc) | ⏳ |

### Bloco 2 — Auditoria do legado Chatwoot V19

| Tarefa | Custo estimado | Bloqueia |
|---|---|---|
| Listar inboxes existentes no Chatwoot | 5 min | Plug do nó n8n |
| Identificar inbox conectada ao número oficial UNIC | 5 min | Plug do nó n8n |
| Listar webhooks ativos (Chatwoot → externos) | 10 min | Desligamento de hooks V19 |
| Listar Agent Bots ativos | 5 min | Risco de bot V19 interferir |
| Validar API token usado pelo n8n V19 | 10 min | Permissão de criar conversa via API |

**Custo total da auditoria:** ~35 min. Bloqueia execução do nó de handoff no n8n.

### Bloco 3 — Construção do system prompt da IARA

Concatenar `CONHECIMENTO_ACADEMIA_GREENFIELD.md` + `FAQ_PINECONE_GREENFIELD.md` + regras de tom + documentação das 3 tools num único system prompt de ~10-15k tokens. Testar manualmente no Anthropic Console antes de plugar no n8n.

### Bloco 4 — Implementação n8n (Claude Code)

5-7 nós conforme ARQUITETURA.md vai detalhar. Inclui:
- Webhook receiver Evolution
- Check `ia_ativa`
- Load history de `chat_messages`
- Chamada Sonnet 4.6 com tools
- Execução de tool (3 branches)
- Persist `chat_messages`
- Send via Evolution

### Bloco 5 — Smoke test

3 cenários mínimos do briefing:
1. Lead pergunta preço → resposta com valor correto (sem inventar)
2. Lead pede Aula Experimental → tool agenda via Calendar
3. Lead menciona lesão → linguagem de manejo de carga

---

## Pendências do briefing original (não resolvidas ainda)

| Pendência | Status atual |
|---|---|
| Reaproveitamento Chatwoot V19 | ✅ Decidido reaproveitar — falta auditoria |
| Estrutura final `leads_perfil` reaproveitada | ✅ Resolvido — recriou do zero com 8 colunas enxutas |
| Definição de `clientes_config` mínimo | ✅ Resolvido no schema v1.1 |
| Política de retry quando Evolution API falha | ⏳ Definir em ARQUITETURA.md |
| Política de timeout do Sonnet 4.6 | ⏳ Definir em ARQUITETURA.md |

---

## Próximas 3 ações concretas

1. **Aprovar ARQUITETURA.md** quando entregue — bloqueia execução pelo Code
2. **Auditar Chatwoot V19** (35 min) — bloqueia tool `handoff_humano`
3. **Construir system prompt da IARA v1** — bloqueia teste manual no Console

---

## Métricas de progresso

| Métrica | Valor |
|---|---|
| Docs canônicos prontos | 2/5 |
| Decisões arquiteturais bloqueantes resolvidas | 4/5 |
| Componentes da stack configurados | 1/6 (só Supabase) |
| Smoke tests passando | 0/3 |

---

## Risco em aberto

**Único risco bloqueante:** auditoria do Chatwoot V19 pode revelar acoplamento com fluxo V19 que exige reescrita de integração. Probabilidade baixa (equipe diz que está depurado), mas precisa ser confirmado antes do Claude Code começar a plugar n8n no Chatwoot.

Todos os outros riscos são gerenciáveis dentro do escopo descartável do projeto (45-90 dias).

---

## Riscos técnicos conhecidos (não-bloqueantes, monitorar em runtime)

Decisões tomadas no ARQUITETURA.md que podem virar problema em produção. **Não exigem ação agora**, mas ficam registrados pra revisita rápida se observação real justificar.

| # | Risco | Gatilho pra revisitar | Mitigação se virar problema |
|---|---|---|---|
| 1 | **Histórico limitado a 20 mensagens por turno** | Conversa muito longa onde IARA "esquece" o que lead disse no início | Subir limite para 30-50 OU implementar summary em `leads_perfil.memory_summary` (campo a criar) |
| 2 | **Limite de 5 iterações de tool-use por turno** | Log mostra IARA travando no limite repetidamente | Subir limite OU dividir tools muito amplas em tools menores |
| 3 | **Sem campo `failed` em `chat_messages`** | Evolution API falhar e mensagem da IARA não chegar ao lead, sem rastreabilidade | Adicionar coluna `delivery_status TEXT` com valores `pending/sent/failed` + retry async |
