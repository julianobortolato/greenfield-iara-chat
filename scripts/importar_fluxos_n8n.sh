#!/usr/bin/env bash
# Importa/atualiza fluxo_principal.json no n8n via REST API e ativa o fluxo.
# Uso: N8N_URL=https://... N8N_API_KEY=... ./scripts/importar_fluxos_n8n.sh
#
# Comportamento:
#   - Se fluxo "IARA Chat — Fluxo Principal" já existir → PUT (atualiza)
#   - Se não existir → POST (cria novo)
#   - Ativa o fluxo ao final

set -euo pipefail

: "${N8N_URL:?Variável N8N_URL não definida. Ex: export N8N_URL=https://n8n.fitnessacademia.com.br}"
: "${N8N_API_KEY:?Variável N8N_API_KEY não definida. Ex: export N8N_API_KEY=seu-token}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUXO_PATH="${SCRIPT_DIR}/../n8n/fluxo_principal.json"
FLUXO_NOME="IARA Chat — Fluxo Principal"

if [ ! -f "$FLUXO_PATH" ]; then
  echo "ERRO: Arquivo não encontrado: ${FLUXO_PATH}" >&2
  exit 1
fi

echo "==> Verificando se fluxo já existe em ${N8N_URL} ..."

LISTA=$(curl -sf \
  "${N8N_URL}/api/v1/workflows?limit=100" \
  -H "X-N8N-API-KEY: ${N8N_API_KEY}")

if command -v python3 &>/dev/null; then
  EXISTING_ID=$(echo "$LISTA" | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data.get('data', data) if isinstance(data, dict) else data
for w in items:
    if w.get('name') == '${FLUXO_NOME}':
        print(w.get('id', ''))
        break
" 2>/dev/null || true)
else
  EXISTING_ID=""
fi

if [ -n "$EXISTING_ID" ]; then
  echo "    Fluxo existente encontrado. ID: ${EXISTING_ID}"
  echo "==> Deletando fluxo existente ${EXISTING_ID} ..."
  curl -sf -X DELETE \
    "${N8N_URL}/api/v1/workflows/${EXISTING_ID}" \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    > /dev/null
  echo "    Fluxo deletado."
fi

echo "==> Importando fluxo_principal.json ..."

RESPONSE=$(curl -sf -X POST \
  "${N8N_URL}/api/v1/workflows" \
  -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
  -H "Content-Type: application/json" \
  --data-binary "@${FLUXO_PATH}")

if command -v python3 &>/dev/null; then
  WORKFLOW_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
else
  WORKFLOW_ID=$(echo "$RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  if [ -z "$WORKFLOW_ID" ]; then
    WORKFLOW_ID=$(echo "$RESPONSE" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
  fi
fi

if [ -z "$WORKFLOW_ID" ]; then
  echo "ERRO: Não foi possível extrair o ID do fluxo criado." >&2
  echo "Resposta da API:" >&2
  echo "$RESPONSE" >&2
  exit 1
fi

echo "    Fluxo importado. ID: ${WORKFLOW_ID}"

echo "==> Ativando fluxo ${WORKFLOW_ID} ..."

curl -sf -X POST \
  "${N8N_URL}/api/v1/workflows/${WORKFLOW_ID}/activate" \
  -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
  > /dev/null

echo "    Fluxo ativado."
echo ""
echo "==> PRÓXIMOS PASSOS:"
echo "    1. Abra o fluxo no n8n UI e configure a credencial do nó 'Nó Calendar'"
echo "       (usar credencial Google Calendar OAuth2 existente na instância)"
echo "    2. Webhook URL pronto para configurar na Evolution API:"
echo "       ${N8N_URL}/webhook/evolution"
echo ""
echo "==> CURL para configurar webhook Evolution (executar no terminal Easypanel):"
echo "    curl -s -X PUT \"\${EVOLUTION_API_URL}/webhook/set/\${EVOLUTION_INSTANCE}\" \\"
echo "      -H \"apikey: \${EVOLUTION_API_KEY}\" \\"
echo "      -H \"Content-Type: application/json\" \\"
echo "      -d '{\"url\": \"${N8N_URL}/webhook/evolution\", \"webhook_by_events\": false, \"webhook_base64\": false, \"events\": [\"MESSAGES_UPSERT\"]}'"
