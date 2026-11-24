# TechRental · integração do HTML com o banco MySQL

## O que mudou

| Arquivo | O que faz agora |
|---|---|
| `database/schema.sql` | Banco completo (11 tabelas, views, procedures e dados de exemplo). É o `techrental_completo.sql`, sem alterações. |
| `conexao.php` (novo) | Usa o `$pdo` do `init.php` do projeto. Sem `init.php`, conecta pelas variáveis do `.env`. Ajusta fuso (Brasília) e collation. |
| `login.php` | Confere e-mail e senha na procedure `sp_usuario_login` e abre a **sessão PHP**. |
| `api.php` (novo) | Única porta de entrada das telas: lê dados (`?a=dados`) e executa as ações (aprovar, devolver, cadastrar...). |
| `js/app.js` | Os dados fictícios saíram. Cada tela carrega do banco e cada botão grava no banco. O visual não mudou. |

As páginas `.html` e os `.css` continuam iguais.

## Como instalar no projeto do grupo

1. Copie **o conteúdo** desta pasta para `app/` do fork (HTML, `css/`, `js/`, `img/`, `api.php`, `conexao.php`, `login.php`).
2. Copie `database/schema.sql` por cima do `database/schema.sql` do fork.
3. No `.env`, o **nome do banco precisa ser `techrental`** (é o nome usado dentro do schema.sql). Defina isso antes da primeira execução.
4. Recrie o banco, porque o `schema.sql` só roda quando o volume é criado:

```
docker compose down -v
docker compose up -d --build
```

5. Abra http://localhost:8080/login.html

Logins de teste (senha `12345678`): `almoxarifado@`, `gestor.software@`, `gestor.pd@`, `gestor.campo@`, `gestor.suporte@`, `diretoria@` + `techrental.com`.

## Regras de segurança já aplicadas

- O perfil e o id do usuário vêm **da sessão PHP**, nunca do navegador. Alterar o `sessionStorage` não dá acesso a nada.
- Gestor só recebe do servidor os dados do **próprio setor**.
- Cada ação confere o perfil no PHP **e** dentro das procedures do banco.
- Toda gravação exige o cabeçalho `X-TR` (barra requisições vindas de outros sites).
- Senhas novas são gravadas com `password_hash` (bcrypt).

## Antes de publicar de verdade

- Tire a senha `12345678` pré-preenchida da tela de login (`R.login` no `app.js`).
- O `schema.sql` começa com `DROP DATABASE`. Remova essa linha quando houver dados reais.
- O atraso é calculado pela data real. Os dados de exemplo têm datas de 2026-11, então muitos itens aparecem como atrasados.
