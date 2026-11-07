#!/usr/bin/env bash
# Acessa uma VPS por SSH usando a chave do projeto.
#   scripts/vps.sh                     abre um shell na VPS-00 (Coolify)
#   scripts/vps.sh 'docker ps'         executa um comando na VPS-00
#   scripts/vps.sh vps-01 ['cmd']      o mesmo na VPS-01 (servidor gerenciado pelo Coolify)
# Requer os segredos abertos: scripts/secrets.sh decrypt
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

load() { [[ -f "$1" ]] || { echo "erro: $1 não existe. Rode: scripts/secrets.sh decrypt" >&2; exit 1; }
         set -a; . "./$1"; set +a; }

if [[ "${1:-}" == vps-01 ]]; then
  shift; load .env.vps-01
  HOST="$VPS_IP"; SSH_USER="$VPS_SSH_USER"; KEY="$VPS_SSH_KEY_FILE"
else
  [[ "${1:-}" == vps-00 ]] && shift
  load .env.coolify
  HOST="$COOLIFY_SERVER_IP"; SSH_USER="$COOLIFY_SERVER_SSH_USER"; KEY="$COOLIFY_SERVER_SSH_KEY_FILE"
fi

# Chave de host fixada no repo: se a VPS trocar de chave, o SSH recusa.
exec ssh -i "$KEY" -o IdentitiesOnly=yes \
  -o UserKnownHostsFile=infra/vps/known_hosts -o StrictHostKeyChecking=yes \
  "${SSH_USER}@${HOST}" "$@"
