#!/usr/bin/env bash
# Gera o compose do recurso `openlead-db` (Coolify) a partir do repo do OpenLead.
#
#   infra/openlead/render-db.sh <pasta do repo openlead>
#
# Saída: infra/openlead/openlead-db.coolify.yml (é o texto que vai para o Coolify).
#
# Enquanto o backup não estiver ligado (vai para o S3 da Contabo, decisão do Renan em 2026-11-07),
# o compose sai com DUAS mudanças em relação ao render oficial do OpenLead:
#   1. as variáveis PGBACKREST_REPO1_* deixam de ser obrigatórias (`:?` vira `:-`);
#   2. `archive_mode = off` no postgresql.conf (sem repositório, o WAL se acumularia até encher o disco).
# A imagem continua a com pgBackRest: ligar o backup depois é só mandar o render oficial
# (sem este script) com as variáveis preenchidas, e reiniciar o banco.
set -euo pipefail

SRC="${1:?uso: infra/openlead/render-db.sh <pasta do repo openlead>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/openlead-db.coolify.yml"

raw="$(cd "$SRC" && node infra/coolify/src/render.ts)"
sha="$(git -C "$SRC" rev-parse --short HEAD)"

patched="$(printf '%s\n' "$raw" |
  sed -E 's/\$\{(PGBACKREST_REPO1_[A-Z0-9_]+):\?\}/${\1:-}/' |
  sed -E 's/^([[:space:]]+)archive_mode = on$/\1archive_mode = off/')"

# Confere que as duas mudanças pegaram (se o OpenLead mudar o arquivo, o script para).
[[ "$(grep -c 'PGBACKREST_REPO1_[A-Z0-9_]*:?' <<<"$patched")" == 0 ]] || { echo "erro: sobrou PGBACKREST obrigatória" >&2; exit 1; }
[[ "$(grep -cE '^[[:space:]]+archive_mode = off$' <<<"$patched")" == 1 ]] || { echo "erro: archive_mode não virou off" >&2; exit 1; }

{
  echo "# GERADO por openlead-agente/infra/openlead/render-db.sh a partir do openlead@$sha. Não edite aqui."
  echo "# Variante SEM BACKUP (archive_mode = off, PGBACKREST_* opcionais). Ver o cabeçalho do script."
  printf '%s\n' "$patched"
} > "$OUT"
echo "ok: $OUT (openlead@$sha)"
