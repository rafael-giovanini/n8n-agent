# 05 — Credenciais e segredos (n8n + `.env`)

> **Sumário**
>
> 1. [Visão geral das três credenciais do n8n](#1-visão-geral-das-três-credenciais-do-n8n)
> 2. [Regra dourada: nunca commite segredos](#2-regra-dourada-nunca-commite-segredos)
> 3. [Credencial `Google Gemini API` (chave gratuita no AI Studio)](#3-credencial-google-gemini-api-chave-gratuita-no-ai-studio)
> 4. [Credencial `Postgres Barbearia`](#4-credencial-postgres-barbearia)
> 5. [Credencial `Google Calendar OAuth`](#5-credencial-google-calendar-oauth)
> 6. [Calendário: obter o Calendar ID](#6-calendário-obter-o-calendar-id)
> 7. [Placeholders que devem ser substituídos](#7-placeholders-que-devem-ser-substituídos)
> 8. [Tabela de variáveis do `.env.example` (raiz) e onde cada uma é usada](#8-tabela-de-variáveis-do-envexample-raiz-e-onde-cada-uma-é-usada)
> 9. [Variáveis de `bridge/.env` (resumo)](#9-variáveis-de-bridgeenv-resumo)
> 10. [Alternativa de modelo: OpenAI `gpt-4o-mini`](#10-alternativa-de-modelo-openai-gpt-4o-mini)

---

## 1. Visão geral das três credenciais do n8n

Nomes fixados no contrato (§8) — **não os renomeie**:

| Nome no n8n | Tipo nativo do n8n | Usada por | Conteúdo |
|---|---|---|---|
| `Postgres Barbearia` | `postgres` | Todos os nós `n8n-nodes-base.postgres` do workflow principal, das seis ferramentas e do sync | Host `db`, porta `5432`, usuário/senha/banco do `.env` |
| `Google Gemini API` | `googleGeminiApi` | Nó **Modelo Gemini** (`n8n-nodes-langchain.lmChatGoogleGemini`, `gemini-2.0-flash`) | API key do Google AI Studio |
| `Google Calendar OAuth` | `googleCalendarOAuth2Api` | Nó **Criar Evento Google Calendar** (create/delete) do workflow de sincronização | OAuth2 Google com escopo `https://www.googleapis.com/auth/calendar.events` |

Para cadastrar: no n8n, menu lateral **Credentials** (Credenciais) → **Add credential** → escolha o tipo → preencha → **Save**. Nos nós, selecione a credencial no campo *Credential to connect with*.

---

## 2. Regra dourada: nunca commite segredos

1. Os arquivos `.env` (raiz) e `bridge/.env` contêm segredos e **não devem** ir para o controle de versão; os arquivos versionados são apenas `.env.example` e `bridge/.env.example`, com placeholders.
2. Credenciais do n8n ficam criptografadas no volume `n8n_data` usando `N8N_ENCRYPTION_KEY`; **troque** essa chave no `.env` e nunca a reutilize entre ambientes.
3. Placeholders nos arquivos JSON e `.env.example` seguem o formato `__EXEMPLO__`; nunca cole uma chave real em um arquivo versionado.
4. Chaves vazadas (API key exposta em screenshot, commit público) devem ser revogadas imediatamente no console correspondente e geradas novas.
5. A pasta `bridge/session/` (credenciais da sessão WhatsApp) também não deve ser versionada; mantenha apenas o `.gitkeep`.

---

## 3. Credencial `Google Gemini API` (chave gratuita no AI Studio)

Modelo usado: **`gemini-2.0-flash`** (free tier generoso, bom em pt-BR, nó nativo no n8n).

### 3.1 Obter a chave

1. Acesse `https://aistudio.google.com/` com a conta Google da barbearia.
2. Aceite os termos na primeira abertura.
3. No menu esquerdo, **Get API key** (chave de API) → **Create API key** → crie em um projeto novo ou selecione um existente.
4. Copie a chave (formato `AIza...`). Ela é a credencial direta da API Gemini.

### 3.2 Cadastrar no n8n

1. **Credentials** → **Add credential** → procure **Google Gemini API**.
2. Campo **API Key**: cole a chave.
3. Salve. No workflow principal, abra o nó **Modelo Gemini** (filho do **Agente Gemini (Ferramentas)**: `n8n-nodes-langchain.lmChatGoogleGemini`):
   - Credential: `Google Gemini API`;
   - Modelo: `gemini-2.0-flash`;
   - não altere o nome da credencial.
4. Teste com uma execução simples do workflow (mensagem de boas-vindas); a aba Executions deve mostrar sucesso no agente.

> A chave do AI Studio é a mesma variável `GEMINI_API_KEY` do `.env` da raiz quando a ponta Node/precisa da chave; no n8n ela é guardada na credencial acima.

---

## 4. Credencial `Postgres Barbearia`

### 4.1 Dados de conexão

| Campo no n8n | Valor |
|---|---|
| Host | `db` (nome do serviço no Docker; **não** use `localhost` dentro do n8n) |
| Port | `5432` |
| Database | Valor de `POSTGRES_DB` no `.env` (ex.: `barbearia`) |
| User | Valor de `POSTGRES_USER` (ex.: `barb_user`) |
| Password | Valor de `POSTGRES_PASSWORD` |
| SSL | Desligado/None (contêineres na rede interna do Docker) |
| Schema | `public` (padrão) |

### 4.2 Cadastro

1. **Credentials** → **Add credential** → **Postgres** (tipo `postgres`).
2. Preencha a tabela acima e use **Test connection**; deve retornar sucesso.
3. Salve com o nome exato **`Postgres Barbearia`**.
4. Selecione-a em todos os nós Postgres descritos em [04](04-importacao-workflow-n8n.md#5-configurar-os-nós-postgresql-com-a-credencial).

> Se você acessa o PostgreSQL por ferramenta gráfica fora do Docker (DBeaver/Beekeeper), nesse caso o host é `localhost` e a porta publicada pelo compose; já dentro do n8n o host continua `db`.

---

## 5. Credencial `Google Calendar OAuth`

### 5.1 Criar o projeto e habilitar a API

1. Acesse `https://console.cloud.google.com/` e faça login com a conta da barbearia.
2. **Select a project** (topo) → **New Project** → nome ex.: `barbearia-n8n` → **Create**.
3. No buscador de APIs, abra **Google Calendar API** → **Enable**.

### 5.2 Configurar a tela de consentimento OAuth (OAuth consent screen)

1. Menu **APIs & Services** → **OAuth consent screen**.
2. User Type: **External** (uso com contas Gmail comuns) → **Create**.
3. Preencha nome do app (ex.: `Barbearia n8n`), e-mail de suporte e e-mails de contato; salve e avance.
4. Em **Scopes**, adicione o escopo:
   ```
   https://www.googleapis.com/auth/calendar.events
   ```
   (criar/editar/remover eventos do calendário; leitura básica de calendário já coberta por fluxos de consentimento).
5. Em **Test users**, adicione o e-mail da conta que vai autorizar (enquanto o app não for publicado, só usuários da lista conseguem consentir).

### 5.3 Criar o OAuth Client ID (tipo Web application)

1. **APIs & Services** → **Credentials** → **Create Credentials** → **OAuth client ID**.
2. Application type: **Web application**.
3. Authorized redirect URIs (URI de redirecionamento autorizada) — use a callback padrão do n8n:
   ```
   http://localhost:5678/rest/oauth2-credential/callback
   ```
   > Se o `N8N_PORT` do `.env` for diferente de 5678, troque a porta na URI. Se o n8n for exposto em domínio HTTPS, ajuste a callback para o endereço público correspondente.
4. **Create**. Guarde o **Client ID** e o **Client Secret** (a janela os mostra uma vez; podem ser reabertos depois para cópia).

### 5.4 Cadastrar no n8n e autorizar

1. **Credentials** → **Add credential** → **Google Calendar OAuth2** (tipo `googleCalendarOAuth2Api`).
2. Preencha:
   - **Client ID**: copiado do console;
   - **Client Secret**: copiado do console;
   - **Scope**: `https://www.googleapis.com/auth/calendar.events`;
   - **OAuth Callback / Redirect URL**: confirme a URI da §5.3.
3. Salve; o n8n abre um botão para **Authorize** (login com a conta de teste listada no consentimento) e concede acesso.
4. O nome da credencial deve ser exatamente **`Google Calendar OAuth`**.
5. No nó **Criar Evento Google Calendar**, selecione essa credencial (ver [04](04-importacao-workflow-n8n.md#6-configurar-o-workflow-de-sincronização-com-o-google-calendar)).

---

## 6. Calendário: obter o Calendar ID

1. No Google Calendar web (`https://calendar.google.com`), passe o mouse sobre o calendário desejado (ex.: `Agendamentos Barbearia`) → **Settings and sharing** (Configurações e compartilhamento).
2. Role até **Integrate calendar** (Integrar calendário).
3. Copie **Calendar ID** — tem formato de e-mail:
   ```
   exempibarberia@gmail.com
   ```
   ou, em calendários criados por outra conta compartilhada:
   ```
   xxxxxxxxxxxxxxxx@group.calendar.google.com
   ```
4. Cole no lugar do placeholder `__GOOGLE_CALENDAR_ID__` no nó do workflow de sincronização e, se a sua ponta de leitura usar, na variável `GOOGLE_CALENDAR_ID` do `.env` raiz.
5. O mesmo calendário é que vai gerar o link ICS usado na assinatura do Apple Calendar (documento [06](06-sincronizacao-apple-calendar.md)).

---

## 7. Placeholders que devem ser substituídos

| Local | Placeholder | Substituído por |
|---|---|---|
| `.env` raiz (cópia de `.env.example`) | `GEMINI_API_KEY=__COLE_SUA_CHAVE__` | API key do Google AI Studio (§3.1) |
| `.env` raiz | `GOOGLE_CALENDAR_ID=__SEU_CALENDARIO__@group.calendar.google.com` | Calendar ID real (§6) |
| `.env` raiz | Valores vazias de `BUSINESS_NAME`, `BUSINESS_ADDRESS`, `BUSINESS_HOURS_TEXT`, `PIX_CHAVE` | Dados reais do estabelecimento (nunca inventados pelo modelo) |
| `workflow-barbearia-whatsapp.json` (após importar, nos nós) | `__TOOL_LIST_SERVICES_ID__` | ID do `tool-list-services` |
| Mesmo local | `__TOOL_AVAILABLE_SLOTS_ID__` | ID do `tool-available-slots` |
| Mesmo local | `__TOOL_BOOK_APPOINTMENT_ID__` | ID do `tool-book-appointment` |
| Mesmo local | `__TOOL_RESCHEDULE_ID__` | ID do `tool-reschedule-appointment` |
| Mesmo local | `__TOOL_CANCEL_ID__` | ID do `tool-cancel-appointment` |
| Mesmo local | `__TOOL_MY_APPOINTMENTS_ID__` | ID do `tool-my-appointments` |
| `workflow-calendar-sync.json` (após importar) | `__GOOGLE_CALENDAR_ID__` | Calendar ID real (§6) |
| `bridge/.env` | `OWNER_NUMBER=5511999990000` | Número secundário no formato internacional |
| `bridge/.env` | `N8N_WEBHOOK_URL` padrão | Confirmar `http://localhost:<N8N_PORT>/webhook/whatsapp/incoming` |

> Os placeholders existem **nos arquivos versionados**; depois de importar para o n8n, a edição dos IDs ocorre na interface do n8n, não no JSON.

---

## 8. Tabela de variáveis do `.env.example` (raiz) e onde cada uma é usada

| Variável | Exemplo/Padrão | Consumidor | Para quê |
|---|---|---|---|
| `POSTGRES_USER` | `barb_user` | Serviço `db` (`POSTGRES_USER`) e credencial `Postgres Barbearia` | Usuário do PostgreSQL; usado tanto na criação do banco quanto na conexão do n8n. |
| `POSTGRES_PASSWORD` | *(defina uma senha forte)* | Serviço `db` e credencial `Postgres Barbearia` | Senha do banco; nunca a exponha em commits. |
| `POSTGRES_DB` | `barbearia` | Serviço `db` e credencial `Postgres Barbearia` | Nome do banco onde `schema.sql`/`seed.sql` são aplicados. |
| `N8N_PORT` | `5678` | `docker-compose.yml` (mapeia `${N8N_PORT:-5678}:5678`) | Porta de acesso ao n8n no navegador e na `N8N_WEBHOOK_URL` da ponte. |
| `N8N_ENCRYPTION_KEY` | *(string longa aleatória)* | Contêiner `n8n` | Criptografa as credenciais salvas no volume `n8n_data`; manter estável entre reinícios. |
| `DB_TYPE` | `postgresdb` | Contêiner `n8n` | Modo de banco do n8n (Postgres gerenciado pelo compose). |
| `DB_POSTGRESDB_HOST` | `db` | Contêiner `n8n` | Host interno do Docker para o PostgreSQL. |
| `DB_POSTGRESDB_PORT` | `5432` | Contêiner `n8n` | Porta interna do PostgreSQL. |
| `DB_POSTGRESDB_USER` / `DB_POSTGRESDB_PASSWORD` / `DB_POSTGRESDB_DATABASE` | Iguais ao `POSTGRES_*` | Contêiner `n8n` | Credenciais do próprio banco de dados do n8n (separado do banco de negócios quando o compose assim o define). |
| `GEMINI_API_KEY` | `__COLE_SUA_CHAVE__` | Pontas de script que chamam a API direta; no n8n equivalente à credencial `Google Gemini API` | Chave da Gemini; veja §3. |
| `GOOGLE_CALENDAR_ID` | `__SEU_CALENDARIO__@group.calendar.google.com` | Workflow de sincronização (nó Google Calendar) | Calendário de destino dos eventos; veja §6. |
| `BUSINESS_NAME` | ex.: `Barbearia Corte Certo` | Prompt/FAQ (`config/agent-prompt.md`) e resumos do agente | Nome exibido nas mensagens e no comprovante. |
| `BUSINESS_ADDRESS` | ex.: `Rua das Flores, 100 – Centro` | FAQ do prompt | Endereço físico; o modelo não pode inventar. |
| `BUSINESS_HOURS_TEXT` | ex.: `Terça a sábado, 9h às 19h; almoço 12h–13h; domingos e segundas fechado` | FAQ do prompt | Texto fixo de horários de funcionamento. |
| `PIX_CHAVE` | ex.: `cnpj@exemplo.com.br` | FAQ do prompt | Chave Pix informada ao cliente; nunca gerar chave aleatória. |
| `CANCEL_MIN_HOURS` | `2` | Lógica de `tool-cancel-appointment` e `tool-reschedule-appointment` | Antecedência mínima (horas) para cancelar/reagendar sem violação de política. |
| `SLOT_INTERVAL_MINUTES` | `30` | Cálculo de slots em `tool-available-slots` (e `working_hours.slot_interval_minutes` do seed) | Granularidade dos horarios oferecidos. |

> Observação do compose: as variáveis de negócio (`BUSINESS_NAME`, `BUSINESS_ADDRESS`, `BUSINESS_HOURS_TEXT`, `PIX_CHAVE`, `CANCEL_MIN_HOURS`, `SLOT_INTERVAL_MINUTES`) também são repassadas ao contêiner `n8n` como ambiente, podendo ser lidas por `$env(...)` nos nós; o `bridge/.env` tem suas próprias variáveis (tabela §9).

---

## 9. Variáveis de `bridge/.env` (resumo)

Detalhes completos em [03-ponte-baileys-whatsapp.md](03-ponte-baileys-whatsapp.md#4-arquivo-env-da-ponte-variáveis).

| Variável | Usada por |
|---|---|
| `N8N_WEBHOOK_URL` | `server.js` ao publicar a §2.1 |
| `PORT` | Servidor Express da ponte (`/send`, `/health`) |
| `SESSION_DIR` | Pasta de estado da sessão (`bridge/session/`) |
| `OWNER_NUMBER` | `requestPairingCode(OWNER_NUMBER)` quando `REQUEST_PAIRING_CODE=true` |
| `REQUEST_PAIRING_CODE` | Escolha QR vs pair code |
| `MESSAGE_TIMEOUT_MS` | Timeout do fetch ao n8n (padrão 25000) |
| `FALLBACK_MESSAGE` | Mensagem de instabilidade enviada em timeout/falha |

---

## 10. Alternativa de modelo: OpenAI `gpt-4o-mini`

Embora o modelo principal seja o Google Gemini `gemini-2.0-flash`, a arquitetura permite trocar somente o nó de linguagem:

1. No n8n, adicionar um nó **OpenAI Chat Model** (`n8n-nodes-langchain.lmChatOpenAi`) com modelo `gpt-4o-mini` e credencial `OpenAiApi` (API key em platform.openai.com).
2. Conectar esse nó no **Agente Gemini (Ferramentas)** no lugar do nó Gemini (as seis ferramentas permanecem as mesmas).
3. Manter o prompt e as ferramentas intactos; o contrato das ferramentas (§4 do contrato) independe do fornecedor do modelo.

Use a alternativa apenas se houver necessidade comercial; o Gemini permanece como recomendação por free tier generoso, desempenho em pt-BR e integração nativa.

Próxima etapa: [06 — Sincronização com Apple Calendar](06-sincronizacao-apple-calendar.md).
