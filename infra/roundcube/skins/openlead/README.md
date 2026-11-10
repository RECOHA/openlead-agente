Roundcube Webmail Skin "OpenLead"
=================================

Skin filho do **Elastic** com o design system do OpenLead: cores navy `#0B1F33` e
verde `#14C47D`, escalas green/slate/blue, fonte Consolas com fallback Inconsolata,
raios de 2/4/8px, anel de foco sólido e Nav navy nos dois temas (claro e escuro).

Fonte dos tokens: `openlead/packages/ui/src/styles/theme.css` e o `DESIGN.md` do
OpenLead. Os logos vêm de `openlead/brand/`.


O QUE MUDA
----------

- **Tela de login** (`templates/login.html`): painel navy com o logo à esquerda e o
  formulário à direita. Abaixo de 768px vira uma coluna só, com o logo em cima.
- **Telas principais** (e-mail, contatos, configurações, redação): só CSS. Todas as
  cores do Elastic são trocadas pelos tokens (`styles/_variables.less`), e as regras
  próprias ficam em `styles/_openlead.less`.
- **Nav** (`templates/includes/menu.html`): ícone do OpenLead no lugar do logo.
- **Página vazia** (`watermark.html`) e **favicon** com o ícone do OpenLead.

Todo o resto (templates, `ui.js`, ícones, bootstrap) vem do Elastic por herança
(`"extends": "elastic"` no `meta.json`).


ATIVAR
------

Em `config/config.inc.php`:

```php
$config['skin'] = 'openlead';
```

O nome "OpenLead Webmail" (login e título da aba) vem do `product_name` definido no
`meta.json` do skin e tem prioridade sobre o `config.inc.php`.

Na imagem Docker oficial: `ROUNDCUBEMAIL_SKIN=openlead`, com esta pasta montada em
`/var/www/html/skins/openlead`. Testado com `roundcube/roundcubemail:1.7.6-apache`.
As fontes LESS do Elastic são iguais na 1.7.6 e no master (1.8-git).


COMPILAR O CSS
--------------

Os `.css` compilados ficam versionados, então o skin funciona sem ferramentas de
build. Depois de mudar um `.less`, recompile pela raiz do Roundcube:

```
make css-openlead
```

Isso gera `styles.css` e `styles.min.css` (e o mesmo para `print` e `embed`). Os dois
são necessários: o `layout.html` do Elastic pede `/styles/styles.css`, e o Roundcube
procura esse arquivo primeiro no skin pai. Por isso o skin filho também precisa ter o
nome não minificado. O Roundcube então serve o `.min.css`.

O mesmo vale para qualquer arquivo com o mesmo nome no Elastic que seja pedido por um
template do Elastic: o arquivo do Elastic vence. Por isso o favicon se chama
`openlead-favicon.ico`, e está configurado no `meta.json`.


MANUTENÇÃO
----------

- `templates/login.html` e `templates/includes/menu.html` são cópias adaptadas das do
  Elastic. Ao atualizar o Roundcube, compare com as versões novas do Elastic.
- Se o design system do OpenLead mudar, atualize os valores em `styles/_tokens.less`
  (mesmos hex do `theme.css`) e recompile.


LICENÇA
-------

Derivado do skin Elastic de Aleksander Machniak / The Roundcube Dev Team, sob a
Creative Commons Attribution-ShareAlike 3.0
(http://creativecommons.org/licenses/by-sa/3.0/). A fonte Inconsolata está sob a SIL
Open Font License (`fonts/OFL.txt`). Os logos do OpenLead pertencem ao OpenLead.
