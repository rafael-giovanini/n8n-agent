# Contrato Compartilhado — Agente de Atendimento de Barbearia no WhatsApp / n8n

> Este arquivo é o **contrato congelado** entre os três blocos de entrega (código da ponte, banco/workflows n8n, documentação). Nenhum bloco pode mudar nomes de tabelas, campos, payload, nomes de ferramentas ou credenciais sem atualizar este arquivo.
> Raiz do projeto (`$ROOT`): `C:\Users\rafae\Dola\chats\2026-11-09\new-chat\barbearia-whatsapp-n8n\`
> Idioma de **todos** os arquivos, comentários, prompts e mensagens: **português brasileiro (pt-BR)**.
> Proibição absoluta: credenciais reais, tokens, números de telefone válidos ou URLs públicas inventadas. Usar sempre placeholders no formato `__EXEMPLO__`.

---

## 1. Mapa de arquivos e donos

| Arquivo (relativo a `$ROOT`) | Dono |
|---|---|
| `README.md` | Docs (A) |
| `docker-compose.yml` | Dados/n8n (B) |
| `.env.example` (raiz) | Dados/n8n (B) |
| `database/schema.sql` | B |
| `database/seed.sql` | B |
| `n8n/workflow-barbearia-whatsapp.json` | B |
| `n8n/workflow-calendar-sync.json` | B |
| `n8n/tools/tool-list-services.json` | B |
| `n8n/tools/tool-available-slots.json` | B |
| `n8n/tools/tool-book-appointment.json` | B |
| `n8n/tools/tool-reschedule-appointment.json` | B |
| `n8n/tools/tool-cancel-appointment.json` | B |
| `n8n/tools/tool-my-appointments.json` | B |
| `bridge/package.json` | Ponte (C) |
| `bridge/server.js` | C |
| `bridge/.env.example` | C |
| `bridge/session/.gitkeep` | C (arquivo vazio) |
| `config/agent-prompt.md` | C |
| `docs/01-arquitetura.md` | Docs (A) |
| `docs/02-instalacao-docker-desktop.md` | A |
| `docs/03-ponte-baileys-whatsapp.md` | A |
| `docs/04-importacao-workflow-n8n.md` | A |
| `docs/05-credenciais-e-segredos.md` | A |
| `docs/06-sincronizacao-apple-calendar.md` | A |
| `docs/07-prompt-e-regras-de-dialogo.md` | A |
| `docs/08-checklist-testes-manuais.md` | A |
| `docs/09-riscos-e-migracao-meta-cloud-api.md` | A |

---

## 2. Contrato de payload (ponte Baileys ↔ n8n) — formato NEUTRO

O adaptador de WhatsApp deve ser **substituível no futuro** pela Meta Cloud API trocando somente a ponte; o n8n nunca vê detalhes do Baileys.

### 2.1 Entrada: ponte → n8n

`POST {N8N_WEBHOOK_URL}` (padrão `http://localhost:5678/webhook/whatsapp/incoming`), `Content-Type: application/json`:

```json
{
  "provider": "baileys",
  "wa_id": "5511999990000",
  "sender_name": "Cliente Exemplo",
  "message_id": "BAILEYS_MSG_ID_ABC123",
  "message_type": "text",
  "message_text": "quero agendar um corte de cabelo",
  "timestamp": 1731100000000
}
```

- `provider`: identifica a origem; a versão futura Meta enviará `"meta"`.
- `wa_id`: número do cliente no formato internacional sem `@s.whatsapp.net`.
- `message_text`: vazio para mídia não textual (a ponte deve avisar o agente com texto genérico).

### 2.2 Resposta síncrona: n8n → ponte

HTTP 200 com:

```json
{
  "messages": [
    { "to": "5511999990000", "type": "text", "text": "Olá! Eu sou a Bia, atendente virtual..." }
  ],
  "human_handoff": false
}
```

- `messages[].text`: cada item vira uma mensagem WhatsApp enviada pela ponte.
- `human_handoff=true`: indica que a pendência foi registrada no n8n (tabela `human_tickets`); a ponte apenas envia a mensagem de aviso de transferência já inclusa em `messages`.

### 2.3 Envio assíncrono: n8n (ou rotina) → ponte

`POST http://localhost:3000/send` (a ponte expõe express na porta definida em `PORT`):

```json
{ "to": "5511999990000", "text": "Seu agendamento foi confirmado..." }
```

Resposta: `{ "ok": true, "sent": true }` ou erro 500 `{ "ok": false, "error": "..." }`.
A ponte também expõe `GET /health` → `{ "status": "ok", "connected": true/false }`.

---

## 3. Banco de dados — PostgreSQL 15+ (`database/schema.sql`)

Extensão obrigatória: `CREATE EXTENSION IF NOT EXISTS btree_gist;`

### 3.1 Tabelas e colunas exatas

**`barbers`**
- `id SERIAL PRIMARY KEY`
- `name TEXT NOT NULL`
- `specialty TEXT`
- `phone TEXT`
- `active BOOLEAN NOT NULL DEFAULT true`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`

**`services`**
- `id SERIAL PRIMARY KEY`
- `name TEXT NOT NULL`
- `description TEXT`
- `duration_minutes INTEGER NOT NULL CHECK (duration_minutes > 0)`
- `price NUMERIC(10,2) NOT NULL CHECK (price >= 0)`
- `active BOOLEAN NOT NULL DEFAULT true`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`

**`clients`**
- `id SERIAL PRIMARY KEY`
- `wa_id TEXT NOT NULL UNIQUE`
- `name TEXT`
- `phone TEXT`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`
- `updated_at TIMESTAMPTZ NOT NULL DEFAULT now()`

**`working_hours`**
- `id SERIAL PRIMARY KEY`
- `day_of_week SMALLINT NOT NULL UNIQUE CHECK (day_of_week BETWEEN 0 AND 6)` (0 = domingo, 6 = sábado)
- `closed BOOLEAN NOT NULL DEFAULT false`
- `open_time TIME`
- `close_time TIME`
- `break_start TIME`
- `break_end TIME`
- `slot_interval_minutes INTEGER NOT NULL DEFAULT 30 CHECK (slot_interval_minutes > 0)`

**`appointments`**
- `id SERIAL PRIMARY KEY`
- `client_id INTEGER NOT NULL REFERENCES clients(id)`
- `service_id INTEGER NOT NULL REFERENCES services(id)`
- `barber_id INTEGER REFERENCES barbers(id)`
- `start_at TIMESTAMPTZ NOT NULL`
- `end_at TIMESTAMPTZ NOT NULL`
- `status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled','confirmed','cancelled','completed','no_show'))`
- `calendar_event_id TEXT`
- `calendar_sync_status TEXT NOT NULL DEFAULT 'pending' CHECK (calendar_sync_status IN ('pending','synced','failed'))`
- `calendar_sync_attempts INTEGER NOT NULL DEFAULT 0`
- `note TEXT`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`
- `updated_at TIMESTAMPTZ NOT NULL DEFAULT now()`
- `CHECK (end_at > start_at)`
- Exclusão anti-conflito (sobre agendamentos ativos):
  `EXCLUDE USING gist (COALESCE(barber_id, 0) WITH =, tstzrange(start_at, end_at, '[)') WITH &&) WHERE (status IN ('scheduled','confirmed'))`

**`conversation_state`**
- `wa_id TEXT PRIMARY KEY`
- `client_id INTEGER REFERENCES clients(id)`
- `state_data JSONB NOT NULL DEFAULT '{}'::jsonb`
- `last_intent TEXT`
- `updated_at TIMESTAMPTZ NOT NULL DEFAULT now()`

**`human_tickets`**
- `id SERIAL PRIMARY KEY`
- `wa_id TEXT NOT NULL`
- `client_id INTEGER REFERENCES clients(id)`
- `name TEXT`
- `reason TEXT`
- `status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_progress','resolved'))`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`
- `updated_at TIMESTAMPTZ NOT NULL DEFAULT now()`

### 3.2 Índices

- `appointments (client_id, start_at)`
- `appointments (status, calendar_sync_status)`
- `clients (wa_id)` (já vem da UNIQUE; não duplicar)
- `conversation_state (updated_at)`

### 3.3 `database/seed.sql` (dados de exemplo, idempotente com `ON CONFLICT`/`WHERE NOT EXISTS`)

- 2 barbeiros: Carlos Souza ("Cortes tradicionais e navalhado"); Felipe Lima ("Degradê e infantil").
- 3 serviços:
  1. Corte de cabelo — 30 min — R$ 35,00
  2. Barba completa — 30 min — R$ 25,00
  3. Combo cabelo + barba — 60 min — R$ 55,00
- `working_hours`: domingo (0) fechado; segunda (1) fechado; terça a sábado (2–6) 09:00–19:00, intervalo 12:00–13:00, slot de 30 min.
- Sem clientes nem agendamentos no seed.

---

## 4. Ferramentas do agente (function calling) — nomes e contratos fixos

Modelo: Google Gemini (`gemini-2.0-flash`; free tier generoso, bom em pt-BR, nó nativo no n8n). Alternativa documentada: OpenAI `gpt-4o-mini`.

| Ferramenta | Args (JSON) | Retorno (JSON) |
|---|---|---|
| `list_services` | `{}` | `{ "services": [{ "service_id": 1, "name": "...", "description": "...", "duration_minutes": 30, "price": "35.00" }] }` |
| `get_available_slots` | `{ "service_id": 1, "date": "YYYY-MM-DD", "barber_id": null }` | `{ "date": "2026-11-10", "closed": false, "slots": ["09:00","09:30",...], "reason": null }` ou `{ "closed": true, "reason": "Fechado às segundas-feiras" }` |
| `book_appointment` | `{ "wa_id": "55...", "client_name": "...", "service_id": 1, "barber_id": null, "start_at": "2026-11-10T09:00:00-03:00" }` | `{ "ok": true, "appointment_id": 10, "start_at": "...", "end_at": "..." }` ou `{ "ok": false, "reason": "conflito"|"fora-expediente"|"passado"|"duracao-indisponivel" }` |
| `reschedule_appointment` | `{ "appointment_id": 10, "wa_id": "55...", "new_start_at": "..." }` | `{ "ok": true, "appointment_id": 10, "start_at": "..." }` ou `{ "ok": false, "reason": "..." }` |
| `cancel_appointment` | `{ "appointment_id": 10, "wa_id": "55...", "reason": "..." }` | `{ "ok": true, "policy_violation": false }` ou `{ "ok": false, "policy_violation": true, "reason": "Cancelamento exige 2h de antecedência" }` |
| `get_my_appointments` | `{ "wa_id": "55..." }` | `{ "appointments": [{ "appointment_id": 10, "service_name": "...", "start_at": "...", "status": "scheduled" }] }` |

Regras de negócio impostas pelas ferramentas (no SQL/lógica dos sub-workflows, **nunca** na língua do modelo):
- Slots respeitam `working_hours`, intervalo de almoço e `closed=true`; horários passados (data/hora < agora) não são oferecidos.
- Duração do serviço define `end_at = start_at + duration_minutes`; o slot só é oferecido se a janela inteira couber.
- Não pode haver sobreposição (exclusão gist do schema); em conflito, `book_appointment` retorna `ok:false`.
- Cancelamento/reagendamento só se `start_at - now >= CANCEL_MIN_HOURS` (padrão 2h); caso contrário `policy_violation=true`.
- `book_appointment` cria/atualiza `clients` por `wa_id`, insere `appointments` com `calendar_sync_status='pending'`; o evento no Google Calendar é criado pelo workflow de sincronização (se falhar, `failed` + tentativas; o agendamento **não** é perdido).

---

## 5. Workflow principal `n8n/workflow-barbearia-whatsapp.json`

JSON válido de importação n8n (estrutura `{ "name", "nodes": [], "connections": {}, "active": false, "settings": {} }`). Conexões de IA usam as chaves `ai_languageModel` e `ai_tool`.

Nós (nome em pt-BR, tipo entre parênteses):

1. **Webhook Recebimento WhatsApp** (`n8n-nodes-base.webhook`) — POST, path `whatsapp/incoming`, `responseMode: "responseNode"`.
2. **Normalizar Mensagem** (`n8n-nodes-base.set`) — mapeia payload neutro; campos `wa_id`, `sender_name`, `message_text`, `message_id`, `timestamp`.
3. **Carregar Estado da Conversa** (`n8n-nodes-base.postgres`) — `SELECT * FROM conversation_state WHERE wa_id = $1`; retorna linha vazia se inexistente.
4. **Agente Gemini (Ferramentas)** (`n8n-nodes-langchain.agent`, `agent: "toolsAgent"`) — conectado a:
   - **Modelo Gemini** (`n8n-nodes-langchain.lmChatGoogleGemini`, `modelName: "gemini-2.0-flash"`, credential `Google Gemini API`);
   - 6 ferramentas `n8n-nodes-langchain.toolWorkflow`, cada uma apontando para o sub-workflow correspondente em `n8n/tools/` (campo `workflowId` com placeholder `__TOOL_<NOME>_ID__`, documentado para preenchimento após importação).
5. **Salvar Estado da Conversa** (`n8n-nodes-base.postgres`) — upsert em `conversation_state` (`state_data`, `last_intent`, `updated_at`).
6. **Verificar Erro** (`n8n-nodes-base.if`) — ramifica se houve erro em qualquer nó:
   - Sucesso → **Montar Resposta Final** (`n8n-nodes-base.code`) que consolida as mensagens do agente no formato `{ "messages": [...], "human_handoff": false }`;
   - Erro → **Registrar Ticket Humano** (`n8n-nodes-base.postgres`, insert em `human_tickets`) → código de fallback com mensagem acolhedora e `human_handoff: true`.
7. **Responder Webhook** (`n8n-nodes-base.respondToWebhook`) — corpo JSON conforme §2.2, status 200.

Comentários de nó (`notes`) em pt-BR explicando cada credencial exigida. Credenciais referenciadas por nome e placeholder de id; sem segredos no JSON.

## 6. Sub-workflows de ferramenta (`n8n/tools/*.json`)

Cada um com `n8n-nodes-base.executeWorkflowTrigger` no início e nós nativos (Postgres `executeQuery`/`insert`/`update` + Code para cálculo de slots) e um nó final `n8n-nodes-base.set` retornando o JSON do §4. Detalhes:

- `tool-list-services`: `SELECT id, name, description, duration_minutes, price FROM services WHERE active = true ORDER BY id`.
- `tool-available-slots`: consulta `working_hours` do dia, `appointments` ativos da data, calcula slots de `slot_interval_minutes` cobrindo a duração do serviço (Code em JS), remove horários passados.
- `tool-book-appointment`: upsert `clients`; valida expansível no expediente; insert em `appointments`; trata erro de exclusão gist como `conflito`; `calendar_sync_status='pending'`.
- `tool-reschedule-appointment`: valida política de antecedência e disponibilidade; `UPDATE start_at/end_at/status`; força `calendar_sync_status='pending'`.
- `tool-cancel-appointment`: valida antecedência; `UPDATE status='cancelled', calendar_sync_status='pending'` (para remover evento depois); registra motivo.
- `tool-my-appointments`: `SELECT ... JOIN services WHERE client_id = (SELECT id FROM clients WHERE wa_id=$1) ORDER BY start_at DESC LIMIT 20`.

## 7. Workflow de sincronização `n8n/workflow-calendar-sync.json`

- **Cron Verificar Pendências** (`n8n-nodes-base.cron`) — a cada 1 minuto.
- **Buscar Agendamentos Pendentes** (`n8n-nodes-base.postgres`) — `WHERE calendar_sync_status IN ('pending','failed') AND calendar_sync_attempts < 5`.
- **Criar Evento Google Calendar** (`n8n-nodes-base.googleCalendar`, operation `create`) — summary `{serviço} - {nome}`, description com barbeiro e telefone, start/end ISO, credential `Google Calendar OAuth`; agenda escolhida via `calendarId` placeholder `__GOOGLE_CALENDAR_ID__`.
- Sucesso → **Marcar Sincronizado** (UPDATE `calendar_sync_status='synced', calendar_event_id=$1`).
- Falha → **Marcar Falha** (UPDATE `calendar_sync_status='failed', calendar_sync_attempts = attempts + 1`); erro capturado por nó de erro que não derruba o fluxo.
- Exclusão de cancelados: rama que consulta `status='cancelled'` com evento existente e remove o evento (operation `delete`), depois limpa `calendar_event_id`.

## 8. Credenciais no n8n (nomes fixos, tipos nativos)

| Nome no n8n | Tipo | O que o usuário preenche |
|---|---|---|
| `Postgres Barbearia` | `postgres` | host `db`, porta `5432`, usuário/senha/DB vindos do `.env` |
| `Google Gemini API` | `googleGeminiApi` | API key do Google AI Studio (placeholder) |
| `Google Calendar OAuth` | `googleCalendarOAuth2Api` | OAuth2 Google com escopo `https://www.googleapis.com/auth/calendar.events` |

## 9. Ponte Baileys (`bridge/`) — contrato mínimo

- `package.json`: `"type": "module"`, deps `@whiskeysockets/baileys` (^6.7.x estável), `express` (^4), `qrcode-terminal` (^0.12), `pino` (^9); script `start`.
- `server.js` (comentários em pt-BR):
  - `useMultiFileAuthState('./session')`; salva credenciais no `creds.update`.
  - QR no terminal com `qrcode-terminal`; se `REQUEST_PAIRING_CODE=true` e não há sessão, `requestPairingCode(OWNER_NUMBER)`.
  - Ignorar grupos (`@g.us`), mensagens próprias (`fromMe`) e status.
  - Texto: `message.conversation || message.extendedTextMessage?.text`; mídia → avisa que só entende texto no momento.
  - POST com `fetch` e timeout `MESSAGE_TIMEOUT_MS` (padrão 25000); para cada `messages[]`, `sock.sendMessage(jid, { text })`.
  - Falha/timeout → fallback amigável de instabilidade; nunca derrubar o processo; reconectar com atraso exponencial no `connection.update.close`.
  - `POST /send`, `GET /health`.
- `bridge/.env.example`: `N8N_WEBHOOK_URL`, `PORT=3000`, `SESSION_DIR=./session`, `OWNER_NUMBER=5511999990000`, `REQUEST_PAIRING_CODE=true`, `MESSAGE_TIMEOUT_MS=25000`, `FALLBACK_MESSAGE` (texto pt-BR de instabilidade).
- `bridge/session/.gitkeep` vazio.

## 10. `config/agent-prompt.md` — seções obrigatórias

1. Identidade: Bia, atendente virtual acolhedora da barbearia; idioma pt-BR; tom amigável, objetivo, mensagens curtas.
2. Boas-vindas (script pronto) e como apresentar serviços.
3. **Regra de ouro**: preços, durações e horários **somente** via ferramentas; nunca inventar; se a ferramenta falhar, pedir aguardo e acionar atendente.
4. Coleta de dados em ordem: nome → serviço (tool) → data/horário (tool) → barbeiro (opcional) → resumo de confirmação antes de gravar.
5. Comprovante de agendamento (nome, serviço, data/hora, barbeiro, duração, valor).
6. Reagendar/cancelar: política de 2h de antecedência; usar ferramentas; nunca alterar sem tool.
7. FAQ: endereço, horários de funcionamento, formas de pagamento (Pix), estacionamento — valores vêm da configuração/env, nunca inventar endereço.
8. Transferência para humano: palavras-chave `atendente`, `falar com alguém`, `pessoa`; registrar motivo e encerrar fluxo automático.
9. Regras estritas de ferramentas (lista as 6) e o que responder quando slot indisponível (oferecer próximos disponíveis).
10. Exemplos curtos de diálogo (boas-vindas, agendamento, cancelamento, transferência).

## 11. `docker-compose.yml` (raiz) e `.env.example` (raiz)

- Serviços: `db` (`postgres:15-alpine`, volume `pg_data`, healthcheck `pg_isready`, variáveis `POSTGRES_USER/PASSWORD/DB`); `n8n` (`n8nio/n8n:latest`, porta `${N8N_PORT:-5678}:5678`, volume `n8n_data:/home/node/.n8n`, env `DB_TYPE=postgresdb`, `DB_POSTGRESDB_HOST=db`, `DB_POSTGRESDB_PORT=5432`, `DB_POSTGRESDB_USER`, `DB_POSTGRESDB_PASSWORD`, `DB_POSTGRESDB_DATABASE`, `N8N_ENCRYPTION_KEY`, depende de `db` com condition `service_healthy`).
- `.env.example` raiz: variáveis do compose + `GEMINI_API_KEY=__COLE_SUA_CHAVE__`, `GOOGLE_CALENDAR_ID=__SEU_CALENDARIO__@group.calendar.google.com`, `BUSINESS_NAME`, `BUSINESS_ADDRESS`, `BUSINESS_HOURS_TEXT`, `PIX_CHAVE`, `CANCEL_MIN_HOURS=2`, `SLOT_INTERVAL_MINUTES=30`.

## 12. Validação obrigatória de cada bloco antes de entregar

- **B**: todos os JSON passam por `JSON.parse` (Node); `docker compose --env-file .env.example config -f docker-compose.yml config` sem erro de sintaxe; `schema.sql` coerente com §3 (todas as tabelas/colunas/citadas em queries existem); `seed.sql` executa semanticamente no Postgres 15.
- **C**: `node --check bridge/server.js` passa; `package.json` faz parse; nenhuma dependência faltante no código (imports só dos deps listados); `.env.example` cobre todas as variáveis lidas no `server.js`.
- **A**: todos os arquivos citados no README existem nos caminhos §1; diagrama Mermaid da arquitetura incluído em `01`; seção de riscos de banimento e guia de migração Meta em `09`; passo a passo pressupõe usuário que nunca usou n8n/Docker.
