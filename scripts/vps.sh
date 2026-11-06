#!/usr/bin/env bash
# Acessa a VPS do Coolify por SSH usando a chave do projeto.
#   scripts/vps.sh                 abre um shell
#   scripts/vps.sh 'docker ps'     executa um comando
# Requer os segredos abertos: scripts/secrets.sh decrypt
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

[[ -f .env.coolify ]] || { echo "erro: .env.coolify não existe. Rode: scripts/secrets.sh decrypt" >&2; exit 1; }
set -a; . ./.env.coolify; set +a

exec ssh -i "$COOLIFY_SERVER_SSH_KEY_FILE" -o IdentitiesOnly=yes \
  "${COOLIFY_SERVER_SSH_USER}@${COOLIFY_SERVER_IP}" "$@"
