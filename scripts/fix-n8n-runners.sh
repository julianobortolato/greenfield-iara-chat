#!/bin/bash
# fix-n8n-runners.sh
# Aplica N8N_RUNNERS_ENABLED=false ao service n8n via Easypanel tRPC API
# e valida que o fluxo IARA executa sem erro de "$env bloqueado".
#
# Uso: bash fix-n8n-runners.sh
# Requer: EASYPANEL_URL, EASYPANEL_API_TOKEN, N8N_API_KEY no ambiente (ou .env)
#
# Referência de API: easypanel-sdk@0.3.1 (tRPC /api/trpc/...)

set -euo pipefail

# ── Carregar .env se existir ────────────────────────────────────────────────
if [ -f "$(dirname "$0")/../.env" ]; then
  set -a; source "$(dirname "$0")/../.env"; set +a
  echo "[info] .env carregado"
fi

# ── Validar variáveis obrigatórias ──────────────────────────────────────────
: "${EASYPANEL_URL:?Variável EASYPANEL_URL não definida}"
: "${EASYPANEL_API_TOKEN:?Variável EASYPANEL_API_TOKEN não definida}"
: "${N8N_API_KEY:?Variável N8N_API_KEY não definida}"

EP="${EASYPANEL_URL%/}"  # remove trailing slash
AUTH="Authorization: $EASYPANEL_API_TOKEN"
CT="Content-Type: application/json"

# ── Helpers ─────────────────────────────────────────────────────────────────
urlencode() {
  python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$1"
}

ep_get() {
  local path="$1" params="$2"
  local encoded
  encoded=$(urlencode "$params")
  curl -sf "$EP$path?input=$encoded" -H "$AUTH" -H "$CT"
}

ep_post() {
  local path="$1" body="$2"
  curl -sf -X POST "$EP$path" -H "$AUTH" -H "$CT" -d "$body"
}

divider() { echo ""; echo "─────────────────────────────────────────────"; echo "$1"; }

# ═══════════════════════════════════════════════════════════════════════════
divider "PASSO 1 — Listar projetos e services"
# ═══════════════════════════════════════════════════════════════════════════
PROJECTS_RAW=$(ep_get "/api/trpc/projects.listProjectsAndServices" '{"json":null}')

echo "$PROJECTS_RAW" | python3 -c "
import sys, json
d = json.load(sys.stdin)
items = d.get('result',{}).get('data',{}).get('json',[]) or []
for p in items:
    pname = p.get('name','')
    svcs = p.get('services', {})
    for kind, lst in svcs.items():
        for s in (lst or []):
            print(f'  [{kind}] project={pname}  service={s.get(\"name\",\"\")}')
"

# ── Detectar automaticamente o service do n8n ──────────────────────────────
N8N_PROJECT=$(echo "$PROJECTS_RAW" | python3 -c "
import sys, json
d = json.load(sys.stdin)
items = d.get('result',{}).get('data',{}).get('json',[]) or []
for p in items:
    for kind, lst in p.get('services',{}).items():
        for s in (lst or []):
            name = s.get('name','').lower()
            if 'n8n' in name:
                print(p['name']); exit()
" 2>/dev/null || true)

N8N_SERVICE=$(echo "$PROJECTS_RAW" | python3 -c "
import sys, json
d = json.load(sys.stdin)
items = d.get('result',{}).get('data',{}).get('json',[]) or []
for p in items:
    for kind, lst in p.get('services',{}).items():
        for s in (lst or []):
            name = s.get('name','').lower()
            if 'n8n' in name:
                print(s['name']); exit()
" 2>/dev/null || true)

if [ -z "$N8N_PROJECT" ] || [ -z "$N8N_SERVICE" ]; then
  echo ""
  echo "[aviso] Não encontrei service com 'n8n' no nome automaticamente."
  read -rp "  Nome do PROJETO no Easypanel: " N8N_PROJECT
  read -rp "  Nome do SERVICE n8n:           " N8N_SERVICE
else
  echo ""
  echo "[detectado] project=$N8N_PROJECT  service=$N8N_SERVICE"
fi

# ═══════════════════════════════════════════════════════════════════════════
divider "PASSO 2 — Inspecionar service e obter env atual"
# ═══════════════════════════════════════════════════════════════════════════
INSPECT_RAW=$(ep_get "/api/trpc/services.app.inspectService" \
  "{\"input\":{\"json\":{\"projectName\":\"$N8N_PROJECT\",\"serviceName\":\"$N8N_SERVICE\"}}}")

CURRENT_ENV=$(echo "$INSPECT_RAW" | python3 -c "
import sys, json
d = json.load(sys.stdin)
svc = d.get('result',{}).get('data',{}).get('json',{}) or {}
print(svc.get('env',''))
" 2>/dev/null || echo "")

echo "Env atual (primeiras 10 linhas):"
echo "$CURRENT_ENV" | head -10
echo "(... total $(echo "$CURRENT_ENV" | wc -l) linhas)"

# ═══════════════════════════════════════════════════════════════════════════
divider "PASSO 3 — Montar nova env + aplicar via updateEnv"
# ═══════════════════════════════════════════════════════════════════════════

# Remover linha N8N_RUNNERS_ENABLED se já existir, depois adicionar no final
NEW_ENV=$(echo "$CURRENT_ENV" | grep -v "^N8N_RUNNERS_ENABLED=" || true)
NEW_ENV=$(printf '%s\nN8N_RUNNERS_ENABLED=false' "$NEW_ENV")

echo "Linha adicionada/sobrescrita: N8N_RUNNERS_ENABLED=false"

# Serializar env como JSON string para o body tRPC
UPDATE_BODY=$(python3 -c "
import json, sys
env = sys.argv[1]
body = {'json': {'projectName': '$N8N_PROJECT', 'serviceName': '$N8N_SERVICE', 'env': env}}
print(json.dumps(body))
" "$NEW_ENV")

UPDATE_RESP=$(ep_post "/api/trpc/services.app.updateEnv" "$UPDATE_BODY")
echo "updateEnv response:"
echo "$UPDATE_RESP" | python3 -m json.tool 2>/dev/null || echo "$UPDATE_RESP"

# Verificar se não houve erro
if echo "$UPDATE_RESP" | grep -q '"error"'; then
  echo "[ERRO] updateEnv falhou — interrompendo"
  exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════
divider "PASSO 4 — Trigger deploy (restart do container)"
# ═══════════════════════════════════════════════════════════════════════════
DEPLOY_BODY=$(python3 -c "
import json
print(json.dumps({'json': {'projectName': '$N8N_PROJECT', 'serviceName': '$N8N_SERVICE'}}))
")

DEPLOY_RESP=$(ep_post "/api/trpc/services.app.deployService" "$DEPLOY_BODY")
echo "deployService response:"
echo "$DEPLOY_RESP" | python3 -m json.tool 2>/dev/null || echo "$DEPLOY_RESP"

if echo "$DEPLOY_RESP" | grep -q '"error"'; then
  echo "[ERRO] deploy falhou"
  exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════
divider "PASSO 5 — Aguardar n8n healthcheck (máx 120s)"
# ═══════════════════════════════════════════════════════════════════════════
echo "Aguardando n8n reiniciar..."
N8N_URL="https://n8n.fitnessacademia.com.br"
TIMEOUT=120
ELAPSED=0
until curl -sf --max-time 5 "$N8N_URL/healthz" > /dev/null 2>&1; do
  if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "[ERRO] n8n não voltou em ${TIMEOUT}s — verificar logs no Easypanel"
    exit 1
  fi
  printf "."
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done
echo ""
echo "[ok] n8n respondeu em ${ELAPSED}s"

# ═══════════════════════════════════════════════════════════════════════════
divider "PASSO 6 — Smoke test: POST no webhook"
# ═══════════════════════════════════════════════════════════════════════════
echo "Enviando payload de teste ao webhook..."
SMOKE_RESP=$(curl -s -w "\n__STATUS:%{http_code}" \
  -X POST "$N8N_URL/webhook/evolution" \
  -H "Content-Type: application/json" \
  -d '{
    "event": "messages.upsert",
    "instance": "Academia_Whats",
    "data": {
      "key": {"remoteJid": "5567999999999@s.whatsapp.net", "fromMe": false, "id": "SMOKE_FIX01"},
      "message": {"conversation": "teste pos fix runners"},
      "messageTimestamp": 1700000010,
      "pushName": "Teste Fix"
    }
  }')

SMOKE_BODY=$(echo "$SMOKE_RESP" | grep -v "__STATUS:")
SMOKE_STATUS=$(echo "$SMOKE_RESP" | grep "__STATUS:" | cut -d: -f2)
echo "HTTP $SMOKE_STATUS — $SMOKE_BODY"

if [ "$SMOKE_STATUS" != "200" ]; then
  echo "[ERRO] Webhook retornou $SMOKE_STATUS — webhook pode estar inativo"
  exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════
divider "PASSO 7 — Consultar última execução no n8n"
# ═══════════════════════════════════════════════════════════════════════════
echo "Aguardando execução ser registrada (5s)..."
sleep 5

EXEC_RESP=$(curl -sf "$N8N_URL/api/v1/executions?limit=1" \
  -H "X-N8N-API-KEY: $N8N_API_KEY")

echo "$EXEC_RESP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
execs = d.get('data', [])
if not execs:
    print('[aviso] Nenhuma execução encontrada — webhook pode ter chegado antes do fluxo estar ativo')
    exit()

e = execs[0]
print(f'execução id={e[\"id\"]} status={e[\"status\"]} startedAt={e.get(\"startedAt\",\"?\")}')

# Verificar erro no Nó 02
rd = (e.get('data') or {})
if isinstance(rd, dict):
    run_data = (rd.get('resultData') or {}).get('runData', {})
    no02 = run_data.get('Nó 02 — Validar HMAC e Filtrar', [])
    if no02:
        err = (no02[0] or {}).get('error')
        if err:
            print(f'[ERRO Nó 02] {err.get(\"message\",err)}')
        else:
            print('[ok] Nó 02 executou sem erro')
            out = (no02[0].get('data') or {}).get('main', [[]])[0]
            if out:
                print(f'  saída: {json.dumps(out[0].get(\"json\",{}), ensure_ascii=False)[:200]}')
    else:
        print('[info] Dados de execução não disponíveis na resposta (pode ser mode=compressed)')
"

# ═══════════════════════════════════════════════════════════════════════════
divider "RESULTADO FINAL"
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "  N8N_RUNNERS_ENABLED=false aplicado ao service '$N8N_SERVICE' (projeto '$N8N_PROJECT')"
echo "  Container reiniciado e n8n respondendo"
echo "  Webhook retornou HTTP 200"
echo ""
echo "  Se o Nó 02 ainda falhar, próximo passo: verificar logs do container via"
echo "  Easypanel → Logs do service '$N8N_SERVICE'"
