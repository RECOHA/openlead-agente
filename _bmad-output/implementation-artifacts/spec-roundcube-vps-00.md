---
title: 'Roundcube na VPS-00 para as contas de e-mail da DreamHost'
type: 'feature'
created: '2026-11-09'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: '7aee613f7e5ea25bdc53549d3b3a2c9aa2e935d0'
context: ['{project-root}/infra/vps/README.md']
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** O Renan quer ler e enviar os e-mails das contas da DreamHost por um webmail próprio, na VPS-00.

**Approach:** Subir a imagem oficial do Roundcube como serviço do Coolify na VPS-00, atrás do Traefik com HTTPS, falando só com os servidores da DreamHost. Os e-mails continuam na DreamHost; o Roundcube guarda só preferências, contatos e assinaturas.

**Decisões do Renan (2026-11-09):**
- Endereço: `email.openlead.app`.
- Sem senha extra no Traefik: a única porta é o login do Roundcube. Risco aceito: robôs podem testar senhas e a DreamHost pode bloquear o IP da VPS-00.
- Uma conta por login, sem plugin de troca de conta.
- Rede do Roundcube isolada do Coolify, com prova no deploy.
- SPEC mantida inteira, acima do alvo de tamanho.

## Boundaries & Constraints

**Always:**
- Imagem com tag exata: `roundcube/roundcubemail:1.7.6-apache`.
- IMAP fixo `ssl://imap.dreamhost.com:993` e SMTP fixo `tls://smtp.dreamhost.com:587`. A tela de login não oferece campo de servidor.
- O contêiner fica só na rede própria do serviço, com `connect_to_docker_network` desligado. Nunca na rede `coolify`, onde estão `coolify`, `coolify-db` e `coolify-redis`. De dentro dele, esses três não podem ser alcançados.
- Sem `ports:` publicadas. Só o Traefik chega nele. Sem `docker.sock`.
- Só `/var/roundcube/db` é volume (SQLite). `/var/www/html` fica fora, para a troca de tag trocar o código.
- `des_key` fixa, em `.env.roundcube.enc`, passada ao Coolify.
- Limite do contêiner: 1 CPU e 512 MB (a VPS-00 tem 7,7 GB, sem swap, e o Coolify é o mais importante ali).

**Never:**
- Hospedar e-mail na VPS (sem Postfix/Dovecot, sem mudar MX ou SPF).
- Abrir porta nova no ufw ou no `openlead-firewall.sh`.
- Mexer no `webmail.openlead.app` nem no `mail.openlead.app` (são da DreamHost).
- Plugin de várias contas ou BasicAuth nesta entrega.
- Backup do volume (perder só custa refazer contatos e assinaturas).
- Guardar senha de e-mail no repo.

## I/O & Edge-Case Matrix

| Cenário | Entrada / Estado | Resultado | Erro |
|---|---|---|---|
| Login | Conta DreamHost válida | Caixa de entrada abre | N/A |
| Enviar | Mensagem com anexo até 25 MB | Sai pelo SMTP da DreamHost | DreamHost recusa: Roundcube mostra o erro e guarda o rascunho |
| Senha errada | Mais de 3 falhas por minuto | Login bloqueado (`login_rate_limit`) | Mensagem na tela |
| HTTP | `http://` no endereço | Redireciona para `https://` | N/A |
| Reinício | Contêiner recriado | Contatos e preferências continuam | N/A |
| Instalador | `GET /installer/` | Não abre o instalador | N/A |

</frozen-after-approval>

## Code Map

- `infra/vps/README.md:18` -- papel da VPS-00 diz "Só o Coolify"; precisa registrar a exceção.
- `infra/vps/README.md:65` -- proxy só muda pela API. Aqui não muda: as rotas vêm de labels do serviço.
- `infra/vps/snapshot/proxy/dynamic/coolify.yaml` -- middleware `redirect-to-https` para reusar (`@file`).
- `infra/vps/snapshot/proxy/docker-compose.yml` -- entrypoints `http`/`https`, resolver `letsencrypt`; `security-headers` já vale para todo HTTPS.
- `infra/openlead/openlead-db.coolify.yml` -- modelo: arquivo de config dentro do compose com `content:`; limites em `deploy.resources`.
- `infra/openlead/README.md:27` -- modelo de runbook e tabela de UUIDs.
- `scripts/secrets.sh` -- `encrypt` já cobre `.env.roundcube` (padrão `.env.*`).
- `scripts/vps.sh`, `scripts/vps-snapshot.sh` -- acesso e foto. O hook `claude_drift.py` exige foto no repo depois de tocar a VPS.
- `.env.coolify` -- `COOLIFY_API_TOKEN` para a API. UUID da VPS-00: `GET /api/v1/servers`, nome `VPS-00 - Contabo Coolify`.
- Não mexer: `infra/vps/docker-compose.custom.yml`, `infra/vps/openlead-firewall.sh`.

## Tasks & Acceptance

**Execution:**
- [x] `infra/roundcube/roundcube.coolify.yml` -- criar o compose (imagem, env, volume, limites, labels do Traefik, `zz-openlead.php` via `content:` em `/var/roundcube/config/`) -- fonte versionada do serviço.
- [x] `.env.roundcube.enc` -- gerar `des_key` de 32 caracteres e rodar `scripts/secrets.sh encrypt` -- segredo fora do repo em texto puro.
- [x] DNS (painel da DreamHost, feito pelo Renan) -- registro A de `email.openlead.app` para `5.253.233.219` -- o certificado depende disso; vem antes do deploy.
- [x] Coolify (API) -- projeto `Pessoal`, ambiente `production`, serviço `roundcube` na VPS-00, `connect_to_docker_network` desligado, variáveis, deploy -- separa do projeto OpenLead.
- [x] `infra/roundcube/README.md` -- UUIDs, como atualizar a tag, o que não tem backup -- runbook.
- [x] `infra/vps/README.md` -- papel da VPS-00 e linha no Histórico -- a doc dizia "só o Coolify".
- [x] `infra/vps/snapshot/` -- rodar `scripts/vps-snapshot.sh` -- foto nova no repo.

**Acceptance Criteria:**
- Given o serviço no ar, when abro o endereço, then vejo HTTPS válido com HSTS e a tela de login sem campo de servidor.
- Given cada conta da DreamHost do Renan, when entro e envio um e-mail para mim, then ele chega e fica na pasta Enviados também no painel da DreamHost.
- Given o serviço no ar, when inspeciono as redes do contêiner, then `coolify` não aparece e o `docker.sock` não está montado.
- Given um shell dentro do contêiner, when tento abrir conexão com `coolify`, `coolify-db` e `coolify-redis`, then as três falham.
- Given o deploy feito, when abro `https://server.openlead.app` e `https://openlead.app/api/health`, then os dois seguem funcionando.

## Implementation Notes

- UUIDs: projeto `Pessoal` `88x1fnddyu2k6iwunva8p1c4`; serviço `roundcube` `0jpqdwhvfa5vdheffsdxlwn6`.
- Labels: o exemplo da Design Notes não dá `rule` nem `entrypoints` ao `roundcube-http`. Sem eles o router não casa com o host; foram acrescentados.
- `zz-openlead.php` também fixa `login_rate_limit = 3` e `enable_installer = false` (iguais ao padrão), porque são requisitos da matriz.
- Divergência em aberto: `http://` responde **307**, não "301 ou 308" como pede Verification. O `redirect-to-https@file` que a spec manda reusar não define `permanent`. Fica como está até o Renan decidir.
- `scripts/secrets.sh encrypt` neste PC recifrou todos os `.enc` (a chave age local não abre os do repo). Os outros 7 foram restaurados com `git restore`; ficou só o `.env.roundcube.enc`, que não dá para decifrar daqui para conferir.

## Spec Change Log

## Review Triage Log

| Achado | Veredito | Evidência | Destino |
|---|---|---|---|
| Prova de isolamento só por nome (blind, edge, gap) | medium | Nome não resolve entre redes Docker; `bool(false)` não provava nada | patch: prova por IP e controle positivo no README; rodada: `false` ×3, `true` ×2 |
| `login_rate_limit` descrito como barreira geral (blind, edge) | medium | `rcmail::login` só chama `is_locked`/`failed_login` com linha em `users`; conta por conta | patch: texto corrigido. Guarda nova rejeitada: o risco de robôs foi aceito no Intent |
| Anexo de 25 MB (blind, edge) | medium | `post_max_size=25M` e `memory_limit=64M` não cabem no multipart | patch: ini com 28M e 256M, valores conferidos no contêiner; envio real segue pendente |
| Provas do runbook incompletas: `http://`, instalador, cookie, campo de servidor, volume (blind, gap) | medium | README só tinha HTTPS 200 e HSTS | patch: rodadas, todas ok |
| Sem aviso de release e sem volta na troca de tag (blind, edge) | medium | SQLite sem backup pode migrar | patch no README |
| Volume guarda sessões com senha cifrada (edge) | low | Tabela `session` fica no mesmo SQLite | patch: uma frase no README |
| Bloqueio da DreamHost sem confirmação nem saída (blind) | low | README parava no diagnóstico | patch no README |
| Persistência só testada localmente (gap) | medium | Faltava prova na VPS | patch: arquivo sentinela sobreviveu à recriação |
| Login, envio e Enviados sem prova com conta real (blind, gap) | medium | Exige senha real, que não deve entrar no repo | defer |
| `http://` responde 307, não 301/308 (blind, gap) | low | Vem do `redirect-to-https@file` que a spec manda reusar; redireciona e o HSTS cobre o resto | rejeitado: corrigir é editar esta spec |
| Exemplo de labels na Design Notes incompleto (blind) | low | Só a spec está errada; o compose está certo | rejeitado: corrigir é editar esta spec |
| Proxy e gateway ainda alcançáveis (blind) | false | Só 22, 80 e 443 escutam fora de loopback, os mesmos abertos à internet; nada novo | rejeitado |
| Falta `proxy_whitelist` (blind, edge) | low | Log guarda IP do Traefik; nada consome esse log e o IP do proxy varia | rejeitado |
| Sem `no-new-privileges`, `cap_drop`, healthcheck (blind) | low | Reforço extra, sem falha demonstrada | rejeitado |
| Snapshot não vê rede por contêiner (gap) | low | Só aparece se alguém mudar a opção; a prova pós-deploy pega; mudar o formato afeta as 3 VPS | rejeitado |
| Saída para a internet sem restrição (edge) | low | Verdade, mas filtrar exige mexer no firewall, proibido pelo Code Map; não dá acesso ao Coolify | rejeitado |
| `.env.roundcube.enc` sem prova de decifrar (blind, gap) | low | Chave deste PC não abre o cofre; a des_key perdida só derruba sessões | rejeitado |
| `RoundCube` e Coolify 4.7.0 fora do Histórico (blind, gap) | false | Registrados em `infra/vps/README.md` no commit 048222c | rejeitado |

## Design Notes

**Por que na VPS-00 exige cuidado:** ela guarda a chave root de todas as VPS. Roundcube é alvo comum de ataques. Por isso a rede separada e sem `docker.sock`: invadir o contêiner não entrega o Coolify.

**Tag fixa = atualização manual:** a 1.7.6 é uma correção de segurança. Cada release de segurança pede trocar a tag e refazer o deploy (runbook).

**Sem BasicAuth, o `login_rate_limit` é a única barreira contra robôs.** Se a DreamHost bloquear o IP, o sintoma é falha de login em todas as contas ao mesmo tempo.

**Labels próprias em vez do domínio do Coolify:** assim a rota fica versionada no compose. Se o Traefik não alcançar o contêiner (504), ligar o `coolify-proxy` à rede do serviço; nunca o inverso.

**`zz-openlead.php`:** `use_https = true` (o TLS termina no Traefik) e `cipher_method = 'AES-256-CBC'` (por isso a chave de 32 caracteres). `ROUNDCUBEMAIL_UPLOAD_MAX_FILESIZE=25M`; não achei o limite oficial de anexo da DreamHost, então 25 MB é escolha minha.

```yaml
- traefik.enable=true
- traefik.http.routers.roundcube-https.rule=Host(`email.openlead.app`)
- traefik.http.routers.roundcube-https.entrypoints=https
- traefik.http.routers.roundcube-https.tls.certresolver=letsencrypt
- traefik.http.routers.roundcube-http.middlewares=redirect-to-https@file
- traefik.http.services.roundcube.loadbalancer.server.port=80
```

## Verification

**Commands:**
- `curl -sI http://email.openlead.app/` -- expected: 301 ou 308 para `https://`
- `curl -sI https://email.openlead.app/` -- expected: 200 e `strict-transport-security`
- `scripts/vps.sh vps-00 'docker inspect roundcube-<uuid> --format "{{json .NetworkSettings.Networks}} {{json .Mounts}}"'` -- expected: sem `coolify` e sem `docker.sock`
- `scripts/vps.sh vps-00 'for a in coolify:8080 coolify-db:5432 coolify-redis:6379; do docker exec roundcube-<uuid> php -r "var_dump(@fsockopen(explode(\":\",\"$a\")[0],(int)explode(\":\",\"$a\")[1],\$e,\$s,3));"; done'` -- expected: `bool(false)` três vezes
- `scripts/vps-snapshot.sh` -- expected: todos os arquivos `OK`

**Manual checks (if no CLI):**
- Entrar com cada conta, ler, enviar com anexo; criar um contato, recriar o contêiner e ver que o contato continua.
