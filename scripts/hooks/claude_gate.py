"""Hook do Claude Code (PreToolUse): nada roda nas VPS, no Coolify ou no cofre sem a liberação do Renan.

Pede confirmação na tela (permissionDecision "ask") para:
  - SSH: scripts/vps.sh, scripts/vps-apply.sh, ssh, scp, sftp, rsync;
  - escrita no Coolify ou em qualquer API: POST/PATCH/PUT/DELETE (curl, requests, urllib, Invoke-RestMethod...);
  - cofre: scripts/secrets.sh, sops, age -d;
  - git push e escrita pelo gh.
Leitura do repo e a foto das VPS (scripts/vps-snapshot.sh, só leitura) seguem sem pedir.
É uma trava contra engano e contra instrução escondida em log, não um cofre: o Renan confere o comando antes de liberar.
No modo auto (e no bypassPermissions) o hook sai do caminho: quem decide é o classificador do modo auto,
igual ao agent-global (lá o Renan pediu isso em 2026-11-04: "pare de perguntar tudo pra mim").
Copiado do agent-global (scripts/hooks/claude_gate.py) e adaptado aos scripts daqui. Ver .claude/settings.json.
"""
import json
import re
import sys

RULES = [
    (r"scripts/vps(-apply)?\.sh|(^|[\s;&|(])(ssh|scp|sftp|rsync)(\.exe)?\s", "SSH numa VPS"),
    (r"\b(POST|PATCH|PUT|DELETE)\s+/(api|servers|applications|services|deployments)\b", "escrita na API do Coolify"),
    (r"\brequests\.(post|patch|put|delete)\b|\bmethod\s*=\s*[\"'](POST|PATCH|PUT|DELETE)", "escrita por HTTP"),
    (r"\b(curl|wget)\b[^\n]*(-X\s*(POST|PATCH|PUT|DELETE)|--request\s+(POST|PATCH|PUT|DELETE)|\s-d\s|--data|-F\s|--form)",
     "escrita por HTTP (curl)"),
    (r"Invoke-(RestMethod|WebRequest)[^\n]*-Method\s+(Post|Patch|Put|Delete)", "escrita por HTTP (PowerShell)"),
    (r"(x-api-key|authorization:)", "chamada HTTP com chave"),
    (r"scripts/secrets\.sh|\bsops(\.exe)?\s|\bage(\.exe)?\s+-d", "abrir ou mexer no cofre"),
    (r"\bgit\s+push\b", "git push"),
    (r"\bgh\s+(api\b[^\n]*(-X|--method)\s*(POST|PATCH|PUT|DELETE)|pr\s+(create|merge)|repo\s+(edit|delete)|release\s+create|secret\s+set)",
     "escrita no GitHub"),
]
COMPILED = [(re.compile(p, re.I), why) for p, why in RULES]


def reason(tool_input):
    cmd = (tool_input or {}).get("command") or ""
    hits = [why for rx, why in COMPILED if rx.search(cmd)]
    return "; ".join(dict.fromkeys(hits)) or None


HANDS_OFF_MODES = {"auto", "bypassPermissions"}


def main():
    data = json.load(sys.stdin)
    if data.get("permission_mode") in HANDS_OFF_MODES:
        return
    why = reason(data.get("tool_input"))
    if why:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": f"Precisa da sua liberação: {why}.",
        }}, ensure_ascii=False))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
