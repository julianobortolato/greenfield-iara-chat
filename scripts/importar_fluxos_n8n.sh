#!/usr/bin/env bash
# Importa fluxo_principal.json no n8n via REST API e ativa o fluxo.
# Uso: N8N_URL=https://... N8N_API_KEY=... ./scripts/importar_fluxos_n8n.sh

set -euo pipefail

: "${N8N_URL:?Variável N8N_URL não definida. Ex: export N8N_URL=https://n8n.fitnessacademia.com.br}"
: "${N8N_API_KEY:?Variável N8N_API_KEY não definida. Ex: export N8N_API_KEY=seu-token}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUXO_PATH="${SCRIPT_DIR}/../n8n/fluxo_principal.json"

if [ ! -f "$FLUXO_PATH" ]; then
  echo "ERRO: Arquivo não encontrado: ${FLUXO_PATH}" >&2
  exit 1
fi

echo "==> Importando fluxo_principal.json para ${N8N_URL} ..."

RESPONSE=$(curl -sf -X POST \
  "${N8N_URL}/api/v1/workflows" \
  -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
  -H "Content-Type: application/json" \
  --data-binary "@${FLUXO_PATH}")

# Extrai o ID do fluxo criado (suporta string e número)
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
echo "Webhook URL pronto para configurar na Evolution API:"
echo "    ${N8N_URL}/webhook/evolution"
