# ARQUITETURA.md — IARA Chat Greenfield

> **Versão:** v1.0 — 16/mai/2026
> **Owner:** Juliano Bortolato
> **Status:** desenho técnico para Claude Code executar

---

## 1. Visão geral do fluxo

```
┌─────────────┐         ┌──────────────────────────────────────────────┐
│   Lead via  │ ──msg──>│            EVOLUTION API V2                  │
│   WhatsApp  │         │   (webhook dispara quando msg chega)         │
└─────────────┘         └──────────────────┬───────────────────────────┘
       ^                                   │ POST /webhook/evolution
       │                                   v
       │              ┌─────────────────────────────────────────────────┐
       │              │                     n8n                         │
       │              │                                                 │
       │              │  ┌──────────────────────────────────────────┐   │
       │              │  │ Nó 1: Webhook In (Evolution)             │   │
       │              │  └──────────────────────────────────────────┘   │
       │              │                  │                              │
       │              │                  v                              │
       │              │  ┌──────────────────────────────────────────┐   │
       │              │  │ Nó 2: Validar HMAC + filtrar evento     │   │
       │              │  └──────────────────────────────────────────┘   │
       │              │                  │                              │
       │              │                  v                              │
       │              │  ┌──────────────────────────────────────────┐   │
       │              │  │ Nó 3: Check ia_ativa (Supabase)         │   │
       │              │  │   - FALSE → STOP (humano cuida)         │   │
       │              │  │   - kill_switch global → STOP           │   │
       │              │  └──────────────────────────────────────────┘   │
       │              │                  │                              │
       │              │                  v                              │
       │              │  ┌──────────────────────────────────────────┐   │
       │              │  │ Nó 4: Persistir msg do lead             │   │
       │              │  │   - INSERT chat_messages (role=user)    │   │
       │              │  │   - UPSERT leads se for primeira msg    │   │
       │              │  └──────────────────────────────────────────┘   │
       │              │                  │                              │
       │              │                  v                              │
       │              │  ┌──────────────────────────────────────────┐   │
       │              │  │ Nó 5: Load history + perfil             │   │
       │              │  │   - SELECT últimas N msgs               │   │
       │              │  │   - SELECT leads_perfil                 │   │
       │              │  └──────────────────────────────────────────┘   │
       │              │                  │                              │
       │              │                  v                              │
       │              │  ┌──────────────────────────────────────────┐   │
       │              │  │ Nó 6: Call Anthropic API                │   │
       │              │  │   - Sonnet 4.6 + system prompt + tools  │   │
       │              │  │   - Receber resposta (texto OU tool_use)│   │
       │              │  └──────────────────────────────────────────┘   │
       │              │                  │                              │
       │              │                  v                              │
       │              │  ┌──────────────────────────────────────────┐   │
       │              │  │ Nó 7: Router de resposta                │   │
       │              │  │   ├─ texto puro → enviar via Evolution  │   │
       │              │  │   ├─ tool_use:salvar_perfil → UPSERT    │   │
       │              │  │   ├─ tool_use:agendar_ae → Calendar     │   │
       │              │  │   └─ tool_use:handoff → Chatwoot + flag │   │
       │              │  └──────────────────────────────────────────┘   │
       │              │                  │                              │
       │              │                  v                              │
       │              │  ┌──────────────────────────────────────────┐   │
       │              │  │ Nó 8: Persistir resposta IARA           │   │
       │              │  │   - INSERT chat_messages (role=assistant)│  │
       │              │  └──────────────────────────────────────────┘   │
       │              │                                                 │
       │              └─────────────────────────────────────────────────┘
       │                                  │
       └──────────────────────────────────┘ POST send-message Evolution
```

**Total: 8 nós no fluxo principal** (briefing previa 5-7; subiu 1 porque persistência foi separada de envio — regra canônica "banco antes de Evolution").

---

## 2. Detalhamento dos nós n8n

### Nó 1 — Webhook In (Evolution)

- **Tipo:** Webhook
- **Método:** POST
- **Path:** `/webhook/evolution`
- **Resposta imediata:** 200 OK (sempre — não bloquear Evolution)
- **Input esperado:** payload Evolution V2 com `data.key.remoteJid`, `data.message.conversation` (ou variantes), `data.messageTimestamp`

### Nó 2 — Validar HMAC + filtrar evento

- **Tipo:** Function (JS)
- **Funções:**
  - Validar header `X-Evolution-Signature` (HMAC SHA-256 com secret do `.env`)
  - Ignorar mensagens do próprio bot (`fromMe: true`)
  - Ignorar tipos não suportados (audio, image, video) na v1 — responder texto padrão "Por enquanto entendo só mensagens de texto"
  - Extrair `remotejid`, `content`, `pushName`

### Nó 3 — Check `ia_ativa`

- **Tipo:** Supabase (SELECT)
- **Query:**
  ```sql
  SELECT l.ia_ativa, c.kill_switch
  FROM leads l, clientes_config c
  WHERE l.remotejid = $1;
  ```
- **Branches:**
  - `kill_switch = TRUE` → STOP, não responde nada
  - `ia_ativa = FALSE` → STOP (humano está no controle via Chatwoot)
  - Lead não existe → segue (próximo nó cria)
  - Ambas OK → segue

### Nó 4 — Persistir mensagem do lead

- **Tipo:** Supabase (UPSERT + INSERT)
- **Operações em transação:**
  ```sql
  INSERT INTO leads (remotejid, nome) VALUES ($1, $2)
  ON CONFLICT (remotejid) DO UPDATE SET updated_at = NOW();

  INSERT INTO chat_messages (remotejid, role, content)
  VALUES ($1, 'user', $3);
  ```
- **Regra canônica:** salvar ANTES de chamar Anthropic. Se Anthropic falhar, mensagem do lead já está persistida.

### Nó 5 — Load history + perfil

- **Tipo:** Supabase (2 SELECTs)
- **Queries:**
  ```sql
  -- Últimas 20 mensagens (ordem cronológica)
  SELECT role, content FROM chat_messages
  WHERE remotejid = $1
  ORDER BY created_at DESC LIMIT 20;
  -- (reverter no n8n para ordem cronológica)

  -- Perfil completo
  SELECT objetivo, historico_treino, restricoes, frequencia, turno_preferido
  FROM leads_perfil WHERE remotejid = $1;
  ```
- **Output:** array de mensagens + objeto perfil pronto pra injetar no prompt

### Nó 6 — Call Anthropic API

- **Tipo:** HTTP Request
- **Endpoint:** `https://api.anthropic.com/v1/messages`
- **Headers:**
  - `x-api-key: {{$env.ANTHROPIC_API_KEY}}`
  - `anthropic-version: 2023-06-01`
  - `content-type: application/json`
- **Body:**
  ```json
  {
    "model": "claude-sonnet-4-6",
    "max_tokens": 1024,
    "system": "<<SYSTEM_PROMPT_IARA>>",
    "messages": [/* histórico + msg atual */],
    "tools": [/* 3 schemas das tools */]
  }
  ```
- **Timeout:** 30 segundos (Sonnet 4.6 com tool use raramente passa de 10s)

### Nó 7 — Router de resposta

- **Tipo:** Switch
- **Lógica:**
  - Parse `response.content[]`
  - Se algum bloco for `type: "tool_use"` → branch correspondente
  - Senão → branch "texto puro" (envia via Evolution)
- **3 branches de tool:**
  - `salvar_perfil` → UPSERT em `leads_perfil` → volta a chamar Anthropic com `tool_result` → repete o nó 7
  - `agendar_aula_experimental` → Google Calendar API (criar evento) → retorna `tool_result` → repete nó 7
  - `handoff_humano` → Chatwoot API (criar/atualizar conversa) + UPDATE `leads SET ia_ativa = FALSE` → retorna `tool_result` → repete nó 7
- **Limite de loop tool-use:** máximo 5 iterações (proteção contra loop infinito do LLM)

### Nó 8 — Persistir resposta IARA + enviar

- **Tipo:** Supabase + HTTP Request (sequencial)
- **Ordem:**
  1. INSERT em `chat_messages` (role='assistant', content=texto final)
  2. POST `/message/sendText` na Evolution API
- **Regra canônica:** persist ANTES de send. Se Evolution falhar, mensagem fica registrada (consistência) e pode ser reenviada por retry.

---

## 3. Contratos das 3 tools (JSON Schema)

### Tool 1 — `salvar_perfil`

```json
{
  "name": "salvar_perfil",
  "description": "Salva dados de qualificação do lead conforme aparecem na conversa. Use sempre que o lead mencionar objetivo, histórico, restrição, frequência ou turno preferido. Não pergunte ativamente — só salve quando o dado já apareceu naturalmente.",
  "input_schema": {
    "type": "object",
    "properties": {
      "objetivo": {
        "type": "string",
        "description": "Objetivo principal do lead. Ex: 'emagrecer', 'ganhar massa', 'saúde', 'reabilitação'"
      },
      "historico_treino": {
        "type": "string",
        "description": "Experiência prévia. Ex: 'nunca treinou', 'treina há 2 anos', 'parou faz 6 meses'"
      },
      "restricoes": {
        "type": "string",
        "description": "Lesões, dores ou restrições médicas mencionadas. Ex: 'dor no joelho direito', 'cirurgia de ombro 2024'"
      },
      "frequencia": {
        "type": "string",
        "description": "Frequência desejada. Ex: '3x por semana', '4x', 'todos os dias'"
      },
      "turno_preferido": {
        "type": "string",
        "description": "Turno. Ex: 'manhã', 'tarde', 'noite', 'final de tarde'"
      }
    }
  }
}
```

**Retorno esperado:** `{"status": "ok", "campos_atualizados": ["objetivo", "restricoes"]}`

---

### Tool 2 — `agendar_aula_experimental`

```json
{
  "name": "agendar_aula_experimental",
  "description": "Agenda Aula Experimental gratuita após o lead confirmar dia e horário específico. NUNCA invente horário — sempre baseie em horário que o lead explicitamente sugeriu e que está dentro do funcionamento da academia (Seg-Sex 5h-21h, Sáb 8h-13h, Dom fechado).",
  "input_schema": {
    "type": "object",
    "properties": {
      "horario_iso": {
        "type": "string",
        "description": "Data e hora no formato ISO 8601 com timezone. Ex: '2026-05-20T18:00:00-04:00' (timezone Campo Grande UTC-4)"
      },
      "nome_lead": {
        "type": "string",
        "description": "Nome do lead conforme ele se apresentou"
      }
    },
    "required": ["horario_iso", "nome_lead"]
  }
}
```

**Retorno esperado:**
- Sucesso: `{"status": "ok", "evento_id": "abc123", "horario_confirmado": "..."}`
- Conflito: `{"status": "ocupado", "sugestao_proximo": "..."}` → IARA propõe horário sugerido

---

### Tool 3 — `handoff_humano`

```json
{
  "name": "handoff_humano",
  "description": "Transfere conversa para atendimento humano via Chatwoot. Use OBRIGATORIAMENTE quando: lead pedir desconto, lead pedir cancelamento, lead falar de questão financeira (boleto, pagamento atrasado, reembolso), lead pedir explicitamente para falar com humano, OU surgir qualquer situação fora do escopo (problema técnico, reclamação séria, etc).",
  "input_schema": {
    "type": "object",
    "properties": {
      "motivo": {
        "type": "string",
        "enum": ["desconto", "cancelamento", "financeiro", "pedido_explicito", "outro"],
        "description": "Categoria do motivo do handoff"
      },
      "contexto": {
        "type": "string",
        "description": "Resumo de 1-2 frases do que o lead quer. Ex: 'Lead João pediu cancelamento — alega que vai mudar de cidade'"
      }
    },
    "required": ["motivo", "contexto"]
  }
}
```

**Retorno esperado:** `{"status": "ok", "conversa_chatwoot_id": 123, "mensagem_para_lead": "Vou te conectar com nosso atendimento humano agora — em instantes alguém vai responder por aqui."}`

---

## 4. Política de retry, timeout e erros

| Componente | Timeout | Retry | Estratégia se falhar |
|---|---|---|---|
| Anthropic API | 30s | 1 retry após 2s | Após 2ª falha → enviar fallback "Tive um problema técnico, pode repetir?" + log |
| Evolution API (send) | 15s | 2 retries com backoff (2s, 5s) | Após 3ª falha → marcar msg como `failed` no banco (campo a adicionar futuramente) + alerta admin |
| Supabase | 10s | Sem retry (falha rápida) | Erro 500 pro webhook — n8n loga e Evolution reenvia |
| Google Calendar | 15s | 1 retry | Se falhar → IARA responde "Tive problema para acessar agenda, te ligo pra confirmar" + handoff |
| Chatwoot | 15s | 2 retries | Se falhar → ainda seta `ia_ativa = FALSE` no banco + log de erro pro admin |

**Princípio:** falhar visível > falhar silencioso. Lead nunca fica sem resposta — IARA tem fallback de texto pra cada cenário.

---

## 5. Fluxo de retorno do Chatwoot (reativar IARA)

```
Atendente clica "Resolver" no Chatwoot
  ↓
Chatwoot dispara webhook conversation_resolved
  ↓
n8n recebe em endpoint separado: POST /webhook/chatwoot
  ↓
Nó: Parse payload → extrair contato.identifier (= remotejid)
  ↓
Nó: UPDATE leads SET ia_ativa=TRUE WHERE remotejid=$1
  ↓
Nó: INSERT chat_messages (role='system', content='[handoff encerrado pela equipe]')
  ↓
END (IARA não envia nada — só volta a estar ativa pra próximas mensagens do lead)
```

**Endpoint do webhook Chatwoot:** `/webhook/chatwoot` (separado do `/webhook/evolution`, sem conflito).

> **Fluxos Chatwoot reutilizados do V19 (não reescrever):**
> Os fluxos n8n abaixo já existem na instância Hostinger, foram depurados nos sprints do V19 e são reaproveitados integralmente pelo Greenfield:
> - **"IARA — Handoff Chatwoot"** — acionado pela tool `handoff_humano`; cria/atualiza conversa no Chatwoot e seta `ia_ativa = FALSE`
> - **"Chatwoot → Reativar IA"** — acionado pelo webhook `conversation_resolved`; seta `ia_ativa = TRUE` e registra nota interna no histórico
>
> Pendência antes de usar: auditoria das inboxes, webhooks e agent bots V19 para identificar o que serve ao Greenfield e o que é resíduo. Ver CLAUDE.md §4.

---

## 6. Variáveis de ambiente necessárias (.env n8n)

```
ANTHROPIC_API_KEY=sk-ant-xxx
EVOLUTION_API_URL=https://evolution.xxx
EVOLUTION_API_KEY=xxx
EVOLUTION_HMAC_SECRET=xxx
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_SERVICE_KEY=eyJxxx
GOOGLE_CALENDAR_ID=primary
GOOGLE_OAUTH_CLIENT_ID=xxx
GOOGLE_OAUTH_CLIENT_SECRET=xxx
CHATWOOT_URL=https://chatwoot.xxx
CHATWOOT_API_TOKEN=xxx
CHATWOOT_INBOX_ID=<a definir pós-auditoria>
CHATWOOT_HMAC_SECRET=xxx
```

**Regra canônica:** todas no `.env` do n8n. Nunca hardcoded em nó. Nunca em frontend (Greenfield não tem frontend, mas regra fica).

---

## 7. Decisões arquiteturais tomadas neste documento

| Decisão | Justificativa |
|---|---|
| Tool use **nativo** Anthropic (não JSON simulado no prompt) | Sonnet 4.6 suporta nativamente, parser de `tool_use` block é estável, n8n consome via HTTP Request normal |
| **8 nós** no fluxo principal (briefing previa 5-7) | Separação banco-antes-de-Evolution força 1 nó a mais — vale a robustez |
| **20 mensagens de histórico** carregadas a cada turno | Equilibra contexto vs custo de token. Ajustável depois |
| **Limite de 5 iterações de tool-use** por turno do lead | Proteção contra loop infinito. Casos reais usam 1-2 iterações |
| **`/webhook/chatwoot` separado** do `/webhook/evolution` | Endpoints diferentes simplificam debug e isolam falhas |
| **Sem campo `failed` em `chat_messages` na v1** | YAGNI — adiciona se observação real de campo justificar |

---

*Fim do ARQUITETURA.md*
