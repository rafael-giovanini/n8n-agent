# 02 — Instalação do Docker Desktop no Windows (subir n8n e PostgreSQL)

> **Sumário**
>
> 1. [O que este passo faz](#1-o-que-este-passo-faz)
> 2. [Pré-requisitos do Windows (WSL2 e virtualização)](#2-pré-requisitos-do-windows-wsl2-e-virtualização)
> 3. [Baixar e instalar o Docker Desktop](#3-baixar-e-instalar-o-docker-desktop)
> 4. [Primeira inicialização do Docker Desktop](#4-primeira-inicialização-do-docker-desktop)
> 5. [Preparar o arquivo `.env` e subir o compose](#5-preparar-o-arquivo-env-e-subir-o-compose)
> 6. [Aplicar os arquivos SQL (schema e seed)](#6-aplicar-os-arquivos-sql-schema-e-seed)
> 7. [Criar a conta proprietária do n8n](#7-criar-a-conta-proprietária-do-n8n)
> 8. [Serviços e volumes do compose](#8-serviços-e-volumes-do-compose)
> 9. [Comandos úteis do dia a dia](#9-comandos-úteis-do-dia-a-dia)
> 10. [Solução de problemas desta etapa](#10-solução-de-problemas-desta-etapa)

---

## 1. O que este passo faz

Antes dos workflows e da ponte, precisamos dos dois serviços de fundo:

- **`db`** — PostgreSQL 15 (imagem `postgres:15-alpine`), onde ficam as 7 tabelas da barbearia;
- **`n8n`** — automação de workflows (imagem `n8nio/n8n:latest`), acessível em `http://localhost:5678`.

Ambos sobem com **um único comando** (`docker compose up -d`) a partir do `docker-compose.yml` da raiz. Nada de PostgreSQL ou n8n precisa ser instalado diretamente no Windows.

---

## 2. Pré-requisitos do Windows (WSL2 e virtualização)

| Requisito | Como verificar / providenciar |
|---|---|
| Windows 10 2004 (Build 19041 ou superior) **ou** Windows 11 | Abrir `winver` no menu Iniciar e conferir a versão. |
| **WSL2** habilitado | Abrir o **PowerShell como Administrador** e executar `wsl --install`; reiniciar o computador quando pedido. |
| Virtualização (VT-x/AMD-V) habilitada na BIOS/UEFI | O Docker Desktop avisa se estiver desativada; em geral fica ligada em máquinas recentes. |
| Espaço em disco | Cerca de 5–10 GB para as imagens e volumes. |

> Se você nunca usou WSL2, após `wsl --install` o computador reinicia e o Ubuntu padrão pode ser instalado automaticamente. Não é preciso configurar nada dentro do Ubuntu para este projeto: o Docker Desktop usa o WSL2 por baixo e você continua trabalhando pelo terminal do Windows.

---

## 3. Baixar e instalar o Docker Desktop

1. Acesse `https://www.docker.com/products/docker-desktop/` e baixe **Docker Desktop for Windows** (instalador `Docker Desktop Installer.exe`, variante x64/AMD64; ARM apenas em PCs Surface ARM).
2. Execute o instalador com duplo clique. Na tela de opções, mantenha marcada a opção **"Use WSL 2 instead of Hyper-V"**.
3. Conclua a instalação e reinicie o computador se solicitado.
4. Ao abrir pela primeira vez, aceite o contrato de uso (a primeira tela permite pular a conta Docker para uso local: **Skip / Continue without signing in**).

---

## 4. Primeira inicialização do Docker Desktop

1. Abra o **Docker Desktop** pelo menu Iniciar.
2. Aguardar até o canto inferior esquerdo mostrar **"Engine running"** (ícone de baleia está sem barra animada).
3. Confirme no terminal (PowerShell ou Git Bash) que o CLI funciona:

```bash
docker --version
docker compose version
```

Os dois comandos devem imprimir versões sem erro. Se o terminal disser que `docker` não é reconhecido, feche e reabra o terminal após instalar o Docker Desktop.

---

## 5. Preparar o arquivo `.env` e subir o compose

### 5.1 Copiar o arquivo de exemplo

Na raiz do projeto (`barbearia-whatsapp-n8n/`) existe `.env.example`. Copie para `.env`:

- **PowerShell:**

```powershell
Copy-Item .env.example .env
```

- **Git Bash:**

```bash
cp .env.example .env
```

Edite o `.env` com o VS Code/Bloco de Notas e preencha, no mínimo:

| Variável | Para quê |
|---|---|
| `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` | Credenciais do serviço `db`; a credencial `Postgres Barbearia` do n8n usará os mesmos valores. |
| `N8N_ENCRYPTION_KEY` | Chave que criptografa credenciais salvas no n8n (troque por uma string longa e aleatória; não compartilhe). |
| `N8N_PORT` | Porta do n8n; padrão `5678`. |
| `GEMINI_API_KEY` | Pode ser preenchida depois (ver [05-credenciais-e-segredos.md](05-credenciais-e-segredos.md)); mas deixe a linha existente no `.env`. |
| `GOOGLE_CALENDAR_ID` | Pode ser preenchida depois com o ID do calendário Google. |
| `BUSINESS_NAME`, `BUSINESS_ADDRESS`, `BUSINESS_HOURS_TEXT`, `PIX_CHAVE` | Dados de FAQ usados pelo prompt; nunca devem ser inventados pelo modelo. |
| `CANCEL_MIN_HOURS=2`, `SLOT_INTERVAL_MINUTES=30` | Política de cancelamento e granularidade dos horários. |

### 5.2 Subir os contêineres

Na raiz do projeto, no terminal:

```bash
docker compose up -d
```

- `-d` significa **detached** (segundo plano); os contêineres continuam rodando após fechar o terminal.
- O primeiro download das imagens (`postgres:15-alpine`, `n8nio/n8n:latest`) pode levar vários minutos dependendo da internet.

### 5.3 Aguardar o healthcheck

Acompanhe o status:

```bash
docker compose ps
```

Espere até o serviço `db` aparecer com **`healthy`**. O `n8n` costuma levar de 30 a 90 segundos para aceitar conexões nos primeiros builds. Acompanhe os logs se necessário:

```bash
docker compose logs -f n8n
```

Pressione `Ctrl + C` para sair dos logs (os contêineres continuam rodando).

### 5.4 Abrir o n8n

Abra no navegador: **`http://localhost:5678`**.

---

## 6. Aplicar os arquivos SQL (schema e seed)

Ordem obrigatória: **primeiro `database/schema.sql`** (cria tabelas e índices), **depois `database/seed.sql`** (insere barbeiros, serviços e expediente). Substitua `barb_user` e `barbearia` pelos valores do seu `.env` caso tenha alterado `POSTGRES_USER` / `POSTGRES_DB`.

### 6.1 Opção A — linha de comando (Git Bash / WSL)

Neste `docker-compose.yml`, o contêiner do banco se chama **`barbearia-db`** (nome do serviço: `db`). A forma mais portável é usar `docker compose exec` (funciona no Git Bash, WSL e PowerShell):

```bash
# Estrutura (schema)
docker compose exec -T db psql -U barb_user -d barbearia < database/schema.sql

# Dados de exemplo (seed)
docker compose exec -T db psql -U barb_user -d barbearia < database/seed.sql
```

Equivalente usando o nome do contêiner direto (esta é a forma do contrato `docker exec -i db ...` quando o contêiner se chama `db`; aqui use `barbearia-db`):

```bash
# Git Bash / WSL — equivalente a: docker exec -i db psql -U barb_user -d barbearia -f /dev/stdin
docker exec -i barbearia-db psql -U barb_user -d barbearia -f /dev/stdin < database/schema.sql
docker exec -i barbearia-db psql -U barb_user -d barbearia -f /dev/stdin < database/seed.sql
```

> No **PowerShell do Windows** não existe `/dev/stdin` nem o operador `<`; use o pipe com `docker compose exec`:

```powershell
Get-Content database/schema.sql | docker compose exec -T db psql -U barb_user -d barbearia
Get-Content database/seed.sql   | docker compose exec -T db psql -U barb_user -d barbearia
```

### 6.2 Opção B — ferramenta gráfica (DBeaver ou Beekeeper Studio)

1. Instale o DBeaver Community ou o Beekeeper Studio.
2. Nova conexão PostgreSQL:
   - Host: `localhost`
   - Porta: `5432` (a porta publicada pelo compose; se o `.env` a tiver alterado, use-a)
   - Usuário: valor de `POSTGRES_USER` (ex.: `barb_user`)
   - Senha: valor de `POSTGRES_PASSWORD`
   - Banco: valor de `POSTGRES_DB` (ex.: `barbearia`)
3. Abra `database/schema.sql`, execute todo o script; depois abra e execute `database/seed.sql`.

### 6.3 Conferência rápida

```bash
docker compose exec -T db psql -U barb_user -d barbearia -c "SELECT name, price, duration_minutes FROM services ORDER BY id;"
```

Espera-se ver os três serviços do seed: Corte de cabelo (R$ 35,00 / 30 min), Barba completa (R$ 25,00 / 30 min) e Combo cabelo + barba (R$ 55,00 / 60 min). Conferir também:

```bash
docker compose exec -T db psql -U barb_user -d barbearia -c "SELECT day_of_week, closed, open_time, close_time FROM working_hours ORDER BY day_of_week;"
```

Domingo (0) e segunda (1) devem vir com `closed = true`; terça a sábado (2–6) com 09:00–19:00.

---

## 7. Criar a conta proprietária do n8n

No primeiro acesso a `http://localhost:5678` o n8n exibe a tela **"Set up owner account"** (criar conta do proprietário):

1. Preencha nome, e-mail e senha (esta conta é local; não enviará dados externos sozinha).
2. Conclua o cadastro e você cairá na tela de workflows.
3. Não ative ainda os workflows: a ordem de importação está em [04-importacao-workflow-n8n.md](04-importacao-workflow-n8n.md).

> Se a tela de setup não aparecer, significa que já existe um banco `n8n_data` de outro projeto; limpe o volume apenas se for um ambiente de teste (`docker compose down -v` remove todos os dados do n8n e do Postgres).

---

## 8. Serviços e volumes do compose

| Serviço | Imagem | Função | Porta | Volume persistente |
|---|---|---|---|---|
| `db` | `postgres:15-alpine` | Banco PostgreSQL 15; healthcheck `pg_isready`; recebe `schema.sql` e `seed.sql` | `5432` (interna; publicada conforme compose) | `pg_data` (dados sobrevivem a `down` e reinícios) |
| `n8n` | `n8nio/n8n:latest` | Automação de workflows; conecta em `db` via `DB_POSTGRESDB_HOST=db`; depende do `db` estar `service_healthy` | `${N8N_PORT:-5678}:5678` | `n8n_data` (definições de workflows e credenciais criptografadas) |

Variáveis do `n8n` definidas no compose: `DB_TYPE=postgresdb`, `DB_POSTGRESDB_HOST=db`, `DB_POSTGRESDB_PORT=5432`, `DB_POSTGRESDB_USER`, `DB_POSTGRESDB_PASSWORD`, `DB_POSTGRESDB_DATABASE`, `N8N_ENCRYPTION_KEY`.

Observações:

- Nomes efetivos dos contêineres neste compose: **`barbearia-db`** (serviço `db`) e **`barbearia-n8n`** (serviço `n8n`); nos comandos `docker compose exec`, usa-se o nome do serviço (`db`, `n8n`); no `docker exec` avulso, usa-se o nome do contêiner.
- A rede interna do Docker usa o nome do serviço como hostname: a credencial Postgres do n8n usa host **`db`** (não `localhost`).
- O `n8n` herda `TZ`/`GENERIC_TIMEZONE = America/Sao_Paulo` e recebe as variáveis de negócio (`BUSINESS_NAME`, `BUSINESS_ADDRESS`, `BUSINESS_HOURS_TEXT`, `PIX_CHAVE`, `CANCEL_MIN_HOURS`, `SLOT_INTERVAL_MINUTES`) declaradas no `.env`.
- A ponte Baileys (`bridge/`) **não** é subida pelo compose — ela roda com Node.js localmente (ver [03](03-ponte-baileys-whatsapp.md)).

---

## 9. Comandos úteis do dia a dia

Todos os comandos são executados **na raiz** do projeto (pasta com `docker-compose.yml`).

| Ação | Comando |
|---|---|
| Subir (ou re-subir) os serviços em segundo plano | `docker compose up -d` |
| Ver status dos contêineres | `docker compose ps` |
| Ver logs do n8n em tempo real | `docker compose logs -f n8n` |
| Ver logs do banco em tempo real | `docker compose logs -f db` |
| Reiniciar apenas o n8n | `docker compose restart n8n` |
| Reiniciar o banco | `docker compose restart db` |
| Parar os serviços mantendo os dados | `docker compose stop` |
| Parar e remover os contêineres (mantém volumes) | `docker compose down` |
| **Apagar também os volumes (CUIDADO: apaga o banco e os workflows)** | `docker compose down -v` |
| Entrar no shell do PostgreSQL | `docker compose exec db psql -U barb_user -d barbearia` (ou `docker exec -it barbearia-db psql -U barb_user -d barbearia`) |
| Recarregar compose após alterar `docker-compose.yml` ou `.env` | `docker compose up -d` |

---

## 10. Solução de problemas desta etapa

| Sintoma | Causa provável | Solução |
|---|---|---|
| `docker: command not found` no terminal | Terminal aberto antes da instalação | Fechar e reabrir o terminal (ou reiniciar) após instalar o Docker Desktop. |
| Docker Desktop trava em "starting" | WSL2 não atualizado ou virtualização desativada | Executar `wsl --update` no PowerShell admin; conferir virtualização na BIOS; reiniciar. |
| `docker compose up -d` falha em bind de porta 5678 | Outro programa usando a porta (ex.: outro n8n local) | Alterar `N8N_PORT` no `.env` para outra porta (ex.: `5679`) e subir novamente. |
| `db` nunca fica `healthy` | Credenciais inconsistentes entre `.env` e variáveis do compose | Conferir que `POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_DB` estão iguais no `.env`; após corrigir, `docker compose down -v` (apenas em ambiente sem dados importantes) e `up -d`. |
| `psql: error: connection refused` ao aplicar SQL | O contêiner `db` ainda não está pronto | Esperar `healthy` em `docker compose ps` e repetir o comando. |
| Tela do n8n não abre em `http://localhost:5678` | n8n ainda iniciando ou erro em logs | `docker compose logs -f n8n`; procurar erro de conexão com `db` (geralmente o banco não estava healthy). |
| Depois de `docker compose down -v` os workflows somem | Volume `n8n_data` apagado | Recriar conta e reimportar os workflows (documento [04](04-importacao-workflow-n8n.md)). |

Próximo passo: [03 — Ponte Baileys (WhatsApp)](03-ponte-baileys-whatsapp.md) ou, se preferir terminar a base primeiro, [04 — Importação dos workflows](04-importacao-workflow-n8n.md).
