# GLOSSARIO_DECISOES.md — IARA Chat Greenfield

> **Versão:** v1.0 — 16/mai/2026
> **Owner:** Juliano Bortolato
> **Propósito:** registrar **por que** cada decisão arquitetural foi tomada. Evita reabrir discussão fechada daqui 30 dias.

---

## Como usar este documento

Cada decisão tem 4 campos:

- **Decisão:** o que ficou definido
- **Alternativas consideradas:** o que foi avaliado e descartado
- **Por que essa:** justificativa em 2-3 linhas
- **Quando reabrir:** condição objetiva que dispararia revisita

Se alguém propuser mudar uma decisão registrada aqui **sem** a condição "quando reabrir" ter sido satisfeita, a resposta padrão é: *"Decisão fechada no Glossário. Pra revisitar, mostra qual gatilho disparou."*

---

## D1 — Arquitetura prompt-first (1 LLM + 3 tools)

**Decisão:** um único LLM (Sonnet 4.6) conduz toda a conversa, com 3 tools disponíveis. Sem máquina de estados, sem multi-agente, sem orquestrador semântico.

**Alternativas consideradas:**
- Máquina de estados explícita com coluna `fase_atual` (modelo V19)
- Multi-agente: classificador → router → especialista por intenção
- Hybrid: LLM principal + LLM auxiliar pra "extração de slots"

**Por que essa:** Sonnet 4.6 é capaz de manter contexto, decidir quando chamar tool, e gerar texto coerente em 1 chamada. Máquina de estados em chat de venda quebra naturalidade da conversa. Multi-agente em projeto descartável é overengineering — 3x mais nós n8n, 3x mais pontos de falha.

**Quando reabrir:** se em piloto observarmos taxa de erro >15% em decisões de quando chamar tool, ou se conversa frequentemente perde contexto crítico.

---

## D2 — Sem RAG / sem Pinecone / sem pgvector

**Decisão:** FAQ (35 chunks) e conhecimento da academia vão **embutidos no system prompt**, não em vector store.

**Alternativas consideradas:**
- Pinecone (era o que o V19 usava)
- pgvector dentro do próprio Supabase
- Embedding em arquivos JSON consultados por tool

**Por que essa:** o FAQ inteiro cabe em ~15k tokens. Sonnet 4.6 tem janela de 200k. Não há razão técnica pra RAG quando o conhecimento inteiro cabe no prompt. RAG adiciona: serviço externo (Pinecone) ou extensão (pgvector), pipeline de ingestão, custo de embedding, latência adicional, risco de top-K errado retornar contexto incompleto. Para 35 chunks, embedding direto perde pra inclusão no prompt.

**Quando reabrir:** se o conhecimento ultrapassar ~50k tokens (3x o atual) ou se aparecer necessidade de conhecimento dinâmico (catálogo de produto, estoque, etc).

---

## D3 — Sonnet 4.6 como modelo único (sem multi-modelo)

**Decisão:** Sonnet 4.6 atende todas as mensagens, independente de complexidade.

**Alternativas consideradas:**
- Haiku 4.5 pra mensagens simples (saudação, confirmação) + Sonnet 4.6 pras complexas
- Modelos third-party (DeepSeek, Gemini Flash, Qwen) na camada barata
- Classificador prévio (modelo barato) decidindo qual modelo principal usar

**Por que essa:** volume esperado da UNIC (~40 leads/mês) × ciclo de vida descartável (45-90 dias) = economia total estimada de ~$24 com multi-modelo. Custo de complexidade (2 nós extras, lógica de roteamento, risco de classificador errar e quebrar tom calibrado) não compensa. Tom da IARA é regra inegociável — risco de modelo barato gerar resposta off-brand é maior que economia.

**Quando reabrir:** se volume crescer pra 500+ conversas/mês ou vida útil estender pra 12+ meses.

---

## D4 — Sem `tenant_id` no schema (sede única)

**Decisão:** nenhuma tabela do Greenfield tem `tenant_id`. Schema é mono-tenant explícito.

**Alternativas consideradas:**
- Manter `tenant_id` como herança defensiva (V19 tinha em tudo)
- Multi-tenant preparado mas não usado

**Por que essa:** Greenfield atende **uma academia** (Fitness UNIC). Coluna `tenant_id` sem uso real polui queries, complica RLS futuras e cria ilusão de capacidade multi-tenant que não existe. Se um dia virar multi-tenant (probabilidade baixa em projeto descartável), `ALTER TABLE ADD COLUMN tenant_id` resolve em minutos.

**Quando reabrir:** se um 2º cliente entrar no escopo (premissa do briefing explicitamente nega isso).

---

## D5 — Banco recriado do zero (sem reaproveitar tabelas V19)

**Decisão:** projeto Supabase novo, schema novo de 4 tabelas. As 18 tabelas V19 não são reaproveitadas.

**Alternativas consideradas:**
- Duplicar projeto Supabase V19 e limpar (Caminho A da análise)
- Reaproveitar tabelas V19 ignorando colunas extras

**Por que essa:** `leads_perfil` do V19 tem 23 colunas das quais Greenfield só usa 6. `leads` tem `fase_atual NOT NULL` (vestígio de FSM). Trigger ativo em `avaliacoes_fisicas` mostra que sistema V19 é vivo e mexer pode contaminar. Recriar custa ~20min vs ~60min de auditoria, com zero risco de vestígio. V19 nunca rodou em produção → não há dado real a preservar.

**Quando reabrir:** nunca. Decisão irreversível neste ciclo.

---

## D6 — Chatwoot V19 reaproveitado (não recriado)

**Decisão:** handoff humano via Chatwoot self-hosted no mesmo servidor Hostinger, instância V19.

**Alternativas consideradas:**
- Chatwoot novo (instância limpa)
- Handoff direto no WhatsApp (sem Chatwoot)

**Por que essa:** equipe familiarizada com a interface (zero retreinamento). Integrações Chatwoot↔Evolution↔n8n já depuradas em sprints anteriores — refazer seria literalmente repetir sofrimento. Custo de auditoria do V19 (~35 min) << custo de setup limpo (4-6h) + treinamento de equipe.

**Quando reabrir:** se auditoria revelar que Chatwoot V19 tem acoplamento estrutural com fluxo V19 que exige refatoração maior que o esforço de instância nova.

---

## D7 — RLS habilitado sem policy (anon negada por padrão)

**Decisão:** todas as tabelas têm `ALTER TABLE ... ENABLE ROW LEVEL SECURITY`, **sem criar policy alguma**.

**Alternativas consideradas:**
- RLS desabilitado (Greenfield não tem frontend, anon não é vetor)
- RLS habilitado com policies específicas
- RLS habilitado com policy permissiva `USING (true)`

**Por que essa:** RLS sem policy = anon completamente negada. Service_role (usada pelo n8n) bypassa RLS sempre — funcionamento intacto. Custo de habilitar é zero, ganho é robustez se anon key vazar acidentalmente. Padrão também alinha com o Supabase Linter (não dispara warning).

**Quando reabrir:** se Greenfield ganhar frontend (improvável) — aí cria policies específicas.

---

## D8 — Tool use nativo Anthropic (não JSON simulado)

**Decisão:** as 3 tools usam o tool use estruturado da API Anthropic (campo `tools` no body), parseando `tool_use` blocks na resposta.

**Alternativas consideradas:**
- Tools simuladas via JSON no prompt ("se quiser agendar, responda com `{action: 'agendar', ...}`")
- Function calling via OpenAI-style schema adaptado

**Por que essa:** Sonnet 4.6 tem suporte nativo, robusto, treinado pra esse formato. JSON simulado tem risco de LLM "esquecer" ou retornar JSON inválido em ~5-10% dos casos. Tool use nativo eleva essa taxa pra <1%.

**Quando reabrir:** se Anthropic depreciar formato atual (improvável no horizonte do projeto).

---

## D9 — Persistência ANTES de envio

**Decisão:** mensagem (do lead e da IARA) é gravada em `chat_messages` **antes** de qualquer chamada externa (Anthropic ou Evolution).

**Alternativas consideradas:**
- Persist depois de send (fluxo otimista)
- Persist em paralelo (async fire-and-forget)

**Por que essa:** se Evolution falhar enviando, mensagem da IARA fica registrada → retry funciona. Se Anthropic falhar, msg do lead já está salva → não perde input. Custo: 1 nó a mais no n8n. Ganho: robustez de retry sem perda de contexto.

**Quando reabrir:** se latência do flow inteiro virar problema observável (lead reclamando de demora). Mesmo assim, otimização vem em outro lugar antes (cache, async tool calls), não removendo persistência.

---

## D10 — Sem fluxo de consentimento LGPD na v1

**Decisão:** Greenfield não implementa captura de consentimento explícito nem direito ao esquecimento automatizado.

**Alternativas consideradas:**
- Consentimento na primeira mensagem (Art. 7º, opt-in explícito)
- Coluna `consentimento_em` em `leads` (preparada mas não usada)
- Endpoint `/excluir-meus-dados` automatizado

**Por que essa:** projeto descartável 45-90 dias com volume baixo. Fricção de consentimento na primeira mensagem reduz engajamento (e o objetivo é converter lead). Se algum lead pedir exclusão no ciclo de vida do projeto, atende manualmente: `DELETE FROM leads WHERE remotejid = X` (CASCADE limpa perfil e mensagens).

**Quando reabrir:** se projeto sair do status descartável (uso > 6 meses ou multi-tenant). Aí entra parecer jurídico antes de implementar.

---

## D11 — Sem features de retenção / aluno ativo

**Decisão:** Greenfield só atende **lead**, não aluno ativo. Sem nudges, sem onboarding pós-matrícula, sem follow-up automatizado de retenção.

**Alternativas consideradas:**
- Incluir mensagens de boas-vindas pós-matrícula
- Mensagem de aniversário, de "saudades" após X dias sem treinar
- Captura de feedback pós-aula

**Por que essa:** retenção é escopo do IARA V2 (sistema paralelo, em piloto, separado deste projeto). Misturar escopos no Greenfield viola princípio de descartabilidade e poderia retroalimentar V2 com decisões erradas. **Regra de ouro do CLAUDE.md:** "Vai pro V2 algum dia, não no Greenfield."

**Quando reabrir:** se V2 for cancelado e Greenfield virar permanente (cenário hipotético, não esperado).

---

## D12 — 8 nós n8n (não 5-7 como briefing previa)

**Decisão:** fluxo principal tem 8 nós no n8n, 1 acima do limite superior do briefing original.

**Alternativas consideradas:**
- Comprimir persistência + envio em 1 nó (caminho original do briefing)
- Quebrar nó 7 (router) em vários switches sequenciais

**Por que essa:** separação "persist antes de enviar" (D9) força nó dedicado. Vale 1 nó a mais pela robustez. Comprimir os 2 numa única transação atômica é frágil quando uma das chamadas é HTTP externa (Evolution).

**Quando reabrir:** nunca como prioridade — número de nós n8n não é gargalo real.

---

## Decisões NÃO documentadas aqui (e por quê)

Decisões operacionais (qual valor exato de timeout, qual threshold de rate limit, qual número de mensagens carregadas no histórico) **não viram entrada do Glossário**. Vivem em ARQUITETURA.md e podem ser ajustadas livremente conforme observação de produção.

O Glossário registra apenas decisões **estruturais** — aquelas que, se revertidas, exigem refatoração ou repensar do projeto inteiro.

---

*Fim do GLOSSARIO_DECISOES.md*
