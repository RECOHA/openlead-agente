"""Hook do Claude Code: o repo tem que ficar igual às VPS depois de cada mexida nelas.

  mark  (PostToolUse, Bash/PowerShell): anota quais VPS o Claude tocou nesta sessão
        (scripts/vps.sh [vps-NN], scripts/vps-apply.sh vps-NN; escrita na API do Coolify = todas).
  stop  (Stop): se alguma VPS foi tocada, tira a foto dela (scripts/vps-snapshot.sh). Barra o fim da resposta
        (uma vez) se um arquivo instalado não bate com infra/vps/, se o .env do Coolify não bate com o cofre,
        ou se a foto mudou e não foi para o git. Se continuar assim, só avisa; a anotação fica para a próxima resposta.

Anotações em .claude/drift/<sessão>.txt (fora do git). A foto precisa dos segredos abertos (scripts/secrets.sh decrypt).
Copiado do agent-global (scripts/hooks/claude_drift.py) e adaptado: aqui a conferência é a foto. Ver .claude/settings.json.
"""
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STATE = ROOT / ".claude" / "drift"
ALL = "*"
VPS_CMD = re.compile(r"scripts/vps(?:-apply)?\.sh(?:[ \t]+[\"']?(vps-\d+))?")
VPS_VAR = re.compile(r"scripts/vps(?:-apply)?\.sh[ \t]+[\"']?\$")   # VPS numa variável (laço): conta como todas
WRITE = re.compile(r"\b(POST|PATCH|PUT|DELETE)\b")
COOLIFY_API = re.compile(r"/api/v1/|\b(POST|PATCH|PUT|DELETE)\s+/(servers|applications|services|deployments)\b")
# Linhas do vps-snapshot.sh que contam como diferença (as de arquivo instalado começam com o caminho absoluto).
BAD = re.compile(r"^\s+(DIFERENTE\b|\?\? /|\?\? \.env)", re.M)


def all_vps():
    """Toda VPS com foto no repo: snapshot/ = vps-00, snapshot-vps-NN/ = vps-NN."""
    out = []
    for d in sorted((ROOT / "infra" / "vps").glob("snapshot*")):
        out.append("vps-00" if d.name == "snapshot" else d.name.removeprefix("snapshot-"))
    return out


def touched(data):
    """VPS que este comando pode ter mudado (ALL = qualquer uma)."""
    cmd = (data.get("tool_input") or {}).get("command") or ""
    found = {m or "vps-00" for m in VPS_CMD.findall(cmd)}
    if VPS_VAR.search(cmd) or (COOLIFY_API.search(cmd) and WRITE.search(cmd)):
        found.add(ALL)
    return found


def mark(data):
    servers = touched(data)
    if not servers:
        return
    STATE.mkdir(parents=True, exist_ok=True)
    f = STATE / f"{data.get('session_id', 'sem-sessao')}.txt"
    old = set(f.read_text().split()) if f.exists() else set()
    f.write_text("\n".join(sorted(old | servers)) + "\n")


def snapshot(vps):
    bash = shutil.which("bash") or "bash"
    r = subprocess.run([bash, "scripts/vps-snapshot.sh", vps], cwd=ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return r.returncode, (r.stdout + r.stderr).strip()


def stop(data):
    f = STATE / f"{data.get('session_id', 'sem-sessao')}.txt"
    if not f.exists():
        return
    marked = set(f.read_text().split())
    servers = all_vps() if ALL in marked else sorted(marked)
    problems = []
    for vps in servers:
        code, out = snapshot(vps)
        if code != 0 or BAD.search(out):
            problems.append(f"### {vps}\n{out[-3000:]}")
    pending = subprocess.run(["git", "status", "--porcelain", "--", "infra/vps"], cwd=ROOT,
                             capture_output=True, text=True, encoding="utf-8", errors="replace").stdout.strip()
    if pending:
        problems.append("### Foto mudou e não foi para o git (git status infra/vps)\n" + pending[-3000:])
    where = ", ".join(servers)
    if not problems:
        f.unlink()
        print(json.dumps({"systemMessage": f"Foto conferida: repo igual às VPS ({where})."}, ensure_ascii=False))
        return
    out = "\n\n".join(problems)
    if not data.get("stop_hook_active"):
        print(json.dumps({"decision": "block", "reason": (
            "O repo não está igual às VPS depois das mudanças nesta resposta. Antes de terminar: "
            "veja o git diff infra/vps, traga para infra/vps/ o que mudou de propósito (ou desfaça na VPS o que "
            "mudou sem querer), registre no Histórico do infra/vps/README.md e faça o commit. "
            f"Saída da conferência ({where}):\n\n" + out[-6000:])}, ensure_ascii=False))
        return
    print(json.dumps({"systemMessage": f"Atenção: o repo ainda está diferente das VPS ({where}). "
                                       "Vai ser conferido de novo no fim da próxima resposta.\n" + out[-1500:]},
                     ensure_ascii=False))


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    data = json.loads(sys.stdin.read() or "{}")
    {"mark": mark, "stop": stop}[sys.argv[1]](data)


if __name__ == "__main__":
    main()
