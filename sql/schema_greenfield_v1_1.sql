-- ============================================================
-- SCHEMA GREENFIELD — IARA Chat WhatsApp (Fitness UNIC)
-- Versão: v1.1 — 16/mai/2026
-- Owner: Juliano Bortolato
-- Arquitetura: prompt-first, sem FSM, sem RAG, sede única
-- ============================================================
-- Execução: cole no SQL Editor do Supabase (projeto NOVO) e rode.
-- Idempotente: pode rodar mais de uma vez sem erro.
-- ============================================================
-- Mudança v1.0 → v1.1: RLS habilitado + policy deny-all para anon.
-- n8n usa service_role (bypassa RLS), então funcionamento não muda.
-- ============================================================


-- ============================================================
-- 1. LEADS — identidade + controle de handoff
-- ============================================================
CREATE TABLE IF NOT EXISTS leads (
  id           BIGSERIAL PRIMARY KEY,
  remotejid    TEXT NOT NULL UNIQUE,
  nome         TEXT,
  cpf          TEXT,
  ia_ativa     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_leads_remotejid ON leads(remotejid);
CREATE INDEX IF NOT EXISTS idx_leads_ia_ativa ON leads(ia_ativa);

COMMENT ON TABLE leads IS 'Lead que conversou com a IARA via WhatsApp';
COMMENT ON COLUMN leads.remotejid IS 'WhatsApp JID, ex: 5567999999999@s.whatsapp.net';
COMMENT ON COLUMN leads.ia_ativa IS 'FALSE quando humano assumiu via Chatwoot — IARA não responde';


-- ============================================================
-- 2. LEADS_PERFIL — qualificação coletada na conversa
-- ============================================================
CREATE TABLE IF NOT EXISTS leads_perfil (
  id                BIGSERIAL PRIMARY KEY,
  remotejid         TEXT NOT NULL UNIQUE REFERENCES leads(remotejid) ON DELETE CASCADE,
  objetivo          TEXT,
  historico_treino  TEXT,
  restricoes        TEXT,
  frequencia        TEXT,
  turno_preferido   TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_leads_perfil_remotejid ON leads_perfil(remotejid);

COMMENT ON TABLE leads_perfil IS 'Dados de qualificação que a IARA captura via tool salvar_perfil';
COMMENT ON COLUMN leads_perfil.objetivo IS 'Texto livre: "emagrecer", "ganhar massa", "saúde", etc';
COMMENT ON COLUMN leads_perfil.restricoes IS 'Lesões, dores, restrições médicas';


-- ============================================================
-- 3. CHAT_MESSAGES — histórico injetado no prompt
-- ============================================================
CREATE TABLE IF NOT EXISTS chat_messages (
  id          BIGSERIAL PRIMARY KEY,
  remotejid   TEXT NOT NULL REFERENCES leads(remotejid) ON DELETE CASCADE,
  role        TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system', 'tool')),
  content     TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_remotejid_created
  ON chat_messages(remotejid, created_at DESC);

COMMENT ON TABLE chat_messages IS 'Histórico de mensagens lead-IARA. Lido pelo n8n e injetado no prompt';
COMMENT ON COLUMN chat_messages.role IS 'user=lead | assistant=IARA | system=prompt sistêmico | tool=resultado de tool call';


-- ============================================================
-- 4. CLIENTES_CONFIG — config da academia (1 linha só)
-- ============================================================
CREATE TABLE IF NOT EXISTS clientes_config (
  id              BIGSERIAL PRIMARY KEY,
  nome_academia   TEXT NOT NULL,
  telefone        TEXT,
  endereco        TEXT,
  ia_ativa_global BOOLEAN NOT NULL DEFAULT TRUE,
  kill_switch     BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE clientes_config IS 'Configuração global da academia. Sempre 1 linha (sede única)';
COMMENT ON COLUMN clientes_config.kill_switch IS 'TRUE = IARA desligada globalmente, todas conversas vão para humano';

-- Seed da Fitness UNIC
INSERT INTO clientes_config (nome_academia, telefone, endereco)
VALUES (
  'Fitness UNIC',
  '(67) 3326-7373',
  'Rua Caconde, 37 — Bairro Santa Fé, Campo Grande/MS'
)
ON CONFLICT DO NOTHING;


-- ============================================================
-- 5. TRIGGER de updated_at automático
-- ============================================================
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_leads_updated_at ON leads;
CREATE TRIGGER trg_leads_updated_at
  BEFORE UPDATE ON leads
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_leads_perfil_updated_at ON leads_perfil;
CREATE TRIGGER trg_leads_perfil_updated_at
  BEFORE UPDATE ON leads_perfil
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_clientes_config_updated_at ON clientes_config;
CREATE TRIGGER trg_clientes_config_updated_at
  BEFORE UPDATE ON clientes_config
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ============================================================
-- 6. RLS — Row Level Security
-- ============================================================
-- Estratégia: habilita RLS em todas as tabelas e NÃO cria policy alguma.
-- Sem policy, anon key é negada por padrão (zero acesso).
-- service_role (usada pelo n8n) bypassa RLS sempre — funcionamento intacto.
-- Se um dia precisar expor leitura pública, criar policy específica.
-- ============================================================

ALTER TABLE leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE leads_perfil ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE clientes_config ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- VERIFICAÇÃO FINAL
-- ============================================================
SELECT 'Schema Greenfield v1.1 criado. RLS habilitado nas 4 tabelas.' AS status;

SELECT
  tablename AS tabela,
  rowsecurity AS rls_ativo
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;
