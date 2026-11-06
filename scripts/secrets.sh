#!/usr/bin/env bash
# Gerencia os segredos do projeto com SOPS + age.
#
#   scripts/secrets.sh init      Cria sua chave age (se faltar) e o .sops.yaml
#   scripts/secrets.sh encrypt   .env.<nome> -> .env.<nome>.enc  |  secrets/<arq> -> secrets/<arq>.enc
#   scripts/secrets.sh decrypt   o inverso (os arquivos abertos são ignorados pelo git)
#   scripts/secrets.sh hooks     Ativa o hook de pre-commit que bloqueia segredos em texto puro
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

# Segredos em texto puro: .env.* em qualquer pasta + qualquer arquivo em secrets/ (exceto .enc)
plain_files() {
  find . -path ./.git -prune -o -type f -name '.env.*' ! -name '*.enc' -print
  [[ -d secrets ]] && find secrets -maxdepth 1 -type f ! -name '*.enc' -print
  true
}
enc_files() {
  find . -path ./.git -prune -o -type f -name '.env.*.enc' -print
  [[ -d secrets ]] && find secrets -maxdepth 1 -type f -name '*.enc' -print
  true
}

# .env.* usam formato dotenv (diff legível: nomes visíveis, valores cifrados); o resto, binário.
sops_type() { case "$(basename "${1%.enc}")" in .env.*) echo dotenv ;; *) echo binary ;; esac; }

# No dotenv o SOPS descarta linhas em branco e garante quebra de linha final;
# normaliza os dois lados para a comparação não acusar mudança falsa.
normalize() { if [[ "$1" == dotenv ]]; then tr -d '\r' | sed -e '/^[[:space:]]*$/d' -e '$a\'; else cat; fi; }

cmd_init() {
  need age-keygen
  if [[ ! -f "$KEY_FILE" ]]; then
    mkdir -p "$(dirname "$KEY_FILE")"
    age-keygen -o "$KEY_FILE"
    chmod 600 "$KEY_FILE" 2>/dev/null || true
    echo "Chave privada criada em: $KEY_FILE  (FAÇA BACKUP — sem ela os segredos não abrem)"
  fi
  local pub
  pub="$(age-keygen -y "$KEY_FILE")"
  if [[ ! -f .sops.yaml ]]; then
    cat > .sops.yaml <<EOF
# Regras do SOPS. Para dar acesso a outra pessoa/máquina, adicione a chave
# pública dela em "age" (separada por vírgula) e rode: sops updatekeys <arquivo>.enc
creation_rules:
  - path_regex: (^|[/\\\\])(\.env(\.[^/\\\\]+)?|secrets[/\\\\][^/\\\\]+)\$
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
  local f out t
  while IFS= read -r f; do
    f="${f#./}"; [[ -z "$f" ]] && continue
    out="$f.enc"; t="$(sops_type "$f")"
    # Só recriptografa se o conteúdo mudou (evita diffs inúteis no git).
    if [[ -f "$out" ]] && cmp -s <(sops decrypt --input-type "$t" --output-type "$t" "$out" 2>/dev/null | normalize "$t") <(normalize "$t" < "$f"); then
      echo "inalterado: $out"
      continue
    fi
    sops encrypt --input-type "$t" --output-type "$t" --filename-override "$out" "$f" > "$out.tmp"
    mv "$out.tmp" "$out"
    echo "criptografado: $f -> $out"
  done < <(plain_files)
}

cmd_decrypt() {
  need sops
  local f out t
  while IFS= read -r f; do
    f="${f#./}"; [[ -z "$f" ]] && continue
    out="${f%.enc}"; t="$(sops_type "$f")"
    (umask 077; sops decrypt --input-type "$t" --output-type "$t" "$f" > "$out.tmp")
    mv "$out.tmp" "$out"
    chmod 600 "$out" 2>/dev/null || true
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
