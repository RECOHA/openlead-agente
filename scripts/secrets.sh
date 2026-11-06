#!/usr/bin/env bash
# Gerencia os segredos .env.* do projeto com SOPS + age.
#
#   scripts/secrets.sh init      Cria sua chave age (se faltar) e o .sops.yaml
#   scripts/secrets.sh encrypt   .env.<nome>      -> .env.<nome>.enc  (versionado)
#   scripts/secrets.sh decrypt   .env.<nome>.enc  -> .env.<nome>      (ignorado pelo git)
#   scripts/secrets.sh hooks     Ativa o hook de pre-commit que bloqueia .env em texto puro
#
# Requer: sops (>= 3.9) e age no PATH.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

if [[ -n "${SOPS_AGE_KEY_FILE:-}" ]]; then
  KEY_FILE="$SOPS_AGE_KEY_FILE"
elif [[ -n "${APPDATA:-}" ]]; then
  KEY_FILE="$APPDATA/sops/age/keys.txt"          # padrão do SOPS no Windows
else
  KEY_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/keys.txt"
fi

need() { command -v "$1" >/dev/null || { echo "erro: '$1' não encontrado no PATH" >&2; exit 1; }; }

# Arquivos .env.* em texto puro (exclui os .enc e o .git)
plain_files() { find . -path ./.git -prune -o -type f -name '.env.*' ! -name '*.enc' -print | sed 's|^\./||'; }
enc_files()   { find . -path ./.git -prune -o -type f -name '.env.*.enc' -print | sed 's|^\./||'; }

cmd_init() {
  need age-keygen
  if [[ ! -f "$KEY_FILE" ]]; then
    mkdir -p "$(dirname "$KEY_FILE")"
    age-keygen -o "$KEY_FILE"
    echo "Chave privada criada em: $KEY_FILE  (FAÇA BACKUP — sem ela os segredos não abrem)"
  fi
  local pub
  pub="$(age-keygen -y "$KEY_FILE")"
  if [[ ! -f .sops.yaml ]]; then
    cat > .sops.yaml <<EOF
# Regras do SOPS. Para dar acesso a outra pessoa/máquina, adicione a chave
# pública dela em "age" (separada por vírgula) e rode: sops updatekeys <arquivo>.enc
creation_rules:
  - path_regex: (^|/)\.env(\.[^/]+)?\$
    age: >-
      $pub
EOF
    echo ".sops.yaml criado com a chave pública: $pub"
  else
    echo ".sops.yaml já existe. Sua chave pública: $pub"
  fi
}

cmd_encrypt() {
  need sops
  local f out
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    out="$f.enc"
    # Só recriptografa se o conteúdo mudou (evita diffs inúteis no git)
    if [[ -f "$out" ]] && diff -q <(sops decrypt --input-type dotenv --output-type dotenv "$out") "$f" >/dev/null 2>&1; then
      echo "inalterado: $out"
      continue
    fi
    sops encrypt --input-type dotenv --output-type dotenv --filename-override "$out" "$f" > "$out.tmp"
    mv "$out.tmp" "$out"
    echo "criptografado: $f -> $out"
  done < <(plain_files)
}

cmd_decrypt() {
  need sops
  local f out
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    out="${f%.enc}"
    sops decrypt --input-type dotenv --output-type dotenv "$f" > "$out.tmp"
    mv "$out.tmp" "$out"
    echo "descriptografado: $f -> $out"
  done < <(enc_files)
}

cmd_hooks() {
  git config core.hooksPath .githooks
  echo "Hooks ativados (core.hooksPath=.githooks)"
}

case "${1:-}" in
  init)    cmd_init ;;
  encrypt) cmd_encrypt ;;
  decrypt) cmd_decrypt ;;
  hooks)   cmd_hooks ;;
  *) sed -n '2,9p' "$0"; exit 1 ;;
esac
