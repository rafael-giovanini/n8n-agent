# 04 — Importação dos workflows no n8n

> **Sumário**
>
> 1. [Visão geral e ordem correta de importação](#1-visão-geral-e-ordem-correta-de-importação)
> 2. [Preparativos antes de importar](#2-preparativos-antes-de-importar)
> 3. [Passo a passo da importação](#3-passo-a-passo-da-importação)
> 4. [Apontar cada ferramenta (`toolWorkflow`) para o sub-workflow importado](#4-apontar-cada-ferramenta-toolworkflow-para-o-sub-workflow-importado)
> 5. [Configurar os nós PostgreSQL com a credencial](#5-configurar-os-nós-postgresql-com-a-credencial)
> 6. [Configurar o workflow de sincronização com o Google Calendar](#6-configurar-o-workflow-de-sincronização-com-o-google-calendar)
> 7. [Ativar os workflows e entender webhook de teste × produção](#7-ativar-os-workflows-e-entender-webhook-de-teste--produção)
> 8. [Campos esperados no webhook de entrada (§2.1)](#8-campos-esperados-no-webhook-de-entrada-21)
> 9. [Acompanhar execuções (Executions list)](#9-acompanhar-execuções-executions-list)
> 10. [Erros comuns de importação](#10-erros-comuns-de-importação)

---

## 1. Visão geral e ordem correta de importação

Existem **oito arquivos JSON** em `n8n/`. A ordem importa porque o workflow principal aponta para os sub-workflows pelo ID interno do n8n (que só existe após a importação):

| Ordem | Arquivo | Tipo | Por quê nesta posição |
|---|---|---|---|
| 1 | `n8n/tools/tool-list-services.json` | Sub-workflow de ferramenta | Referenciado pelo agente principal. |
| 2 | `n8n/tools/tool-available-slots.json` | Sub-workflow de ferramenta | Referenciado pelo agente principal. |
| 3 | `n8n/tools/tool-book-appointment.json` | Sub-workflow de ferramenta | Referenciado pelo agente principal. |
| 4 | `n8n/tools/tool-reschedule-appointment.json` | Sub-workflow de ferramenta | Referenciado pelo agente principal. |
| 5 | `n8n/tools/tool-cancel-appointment.json` | Sub-workflow de ferramenta | Referenciado pelo agente principal. |
| 6 | `n8n/tools/tool-my-appointments.json` | Sub-workflow de ferramenta | Referenciado pelo agente principal. |
| 7 | `n8n/workflow-calendar-sync.json` | Workflow cron de sincronização | Independente, mas precisa da credencial do Google configurada. |
| 8 | `n8n/workflow-barbearia-whatsapp.json` | Workflow principal (webhook + Agente Gemini) | Importado por último, depois de já existirem os IDs das ferramentas. |

> Os sub-workflows de ferramenta **não precisam ser ativados**. Eles são chamados pelo nó `n8n-nodes-langchain.toolWorkflow` através do gatilho `n8n-nodes-base.executeWorkflowTrigger`. Apenas o principal e o de sincronização devem ficar ativos.

---

## 2. Preparativos antes de importar

1. Os contêineres `db` e `n8n` estão no ar (documento [02](02-instalacao-docker-desktop.md)); `http://localhost:5678` abre a tela de workflows.
2. Os SQL já foram aplicados: `database/schema.sql` e `database/seed.sql`.
3. As credenciais mínimas já podem ser criadas (detalhes em [05](05-credenciais-e-segredos.md)):
   - **`Postgres Barbearia`** (tipo `postgres`);
   - **`Google Gemini API`** (tipo `googleGeminiApi`);
   - **`Google Calendar OAuth`** (tipo `googleCalendarOAuth2Api`) — pode ser criada junto com o workflow de sincronização.
4. Saiba que, ao importar, o n8n gera um **ID numérico interno** para cada workflow (visível na URL, ex.: `/workflow/12`). Esse ID é o que vai nos placeholders.

---

## 3. Passo a passo da importação

### 3.1 Importar cada sub-workflow de ferramenta

1. No menu lateral, **Workflows** → botão **Add workflow** (ou use o menu `⋯` no canto superior → **Import from File**).
2. Escolha o arquivo correspondente da tabela da §1 (um de cada vez, na ordem 1–6).
3. O workflow abre com o nome já definido (ex.: `Ferramenta: list_services`).
4. Salve com **Ctrl + S** ou botão **Save**. **Não ative.**
5. Anote o ID na barra de endereço: `http://localhost:5678/workflow/<ID>` — você usará na §4.

### 3.2 Importar `workflow-calendar-sync.json`

1. Mesmo processo de importação.
2. Salve; configure credenciais e calendário na §6.
3. Deixe **inativo** até a §7.

### 3.3 Importar `workflow-barbearia-whatsapp.json`

1. Importe por último.
2. Salve antes de configurar os nós.
3. Abra cada nó conforme as próximas seções, salvando após cada ajuste.

---

## 4. Apontar cada ferramenta (`toolWorkflow`) para o sub-workflow importado

No workflow principal, o nó **Agente Gemini (Ferramentas)** (`n8n-nodes-langchain.agent`, `agent: toolsAgent`) tem seis nós filhos do tipo **`n8n-nodes-langchain.toolWorkflow`**. Cada nó, na primeira importação, fica com um placeholder no campo **Workflow ID** (e, se houver, no campo de versão):

| Nó ferramenta (nome lógico) | Placeholder no JSON | Arquivo importado na §3.1 |
|---|---|---|
| `list_services` | `__TOOL_LIST_SERVICES_ID__` | `n8n/tools/tool-list-services.json` |
| `get_available_slots` | `__TOOL_AVAILABLE_SLOTS_ID__` | `n8n/tools/tool-available-slots.json` |
| `book_appointment` | `__TOOL_BOOK_APPOINTMENT_ID__` | `n8n/tools/tool-book-appointment.json` |
| `reschedule_appointment` | `__TOOL_RESCHEDULE_ID__` | `n8n/tools/tool-reschedule-appointment.json` |
| `cancel_appointment` | `__TOOL_CANCEL_ID__` | `n8n/tools/tool-cancel-appointment.json` |
| `get_my_appointments` | `__TOOL_MY_APPOINTMENTS_ID__` | `n8n/tools/tool-my-appointments.json` |

**Como preencher:**

1. Clique no nó de ferramenta filho do agente.
2. No campo **Workflow ID**, apague o placeholder e cole o ID numérico do workflow correspondente (da URL `/workflow/<ID>`).
3. Se o nó também pedir **Version / Settings**, mantenha o padrão (última versão ativa do sub-workflow).
4. Repita para os seis nós e salve o workflow principal.

> Se o sub-workflow for excluído e recriado, o ID muda: volte nesta etapa e atualize o campo. Não renomeie os arquivos nem os placeholders do contrato.

---

## 5. Configurar os nós PostgreSQL com a credencial

Cada nó tipo `n8n-nodes-base.postgres` deve usar a credencial **`Postgres Barbearia`** (criada conforme [05](05-credenciais-e-segredos.md)).

### 5.1 No workflow principal

| Nó | Operação/Query |
|---|---|
| **Carregar Estado da Conversa** | `SELECT * FROM conversation_state WHERE wa_id = $1` |
| **Salvar Estado da Conversa** | Upsert em `conversation_state` (`state_data`, `last_intent`, `updated_at`) |
| **Registrar Ticket Humano** | Insert em `human_tickets` |

### 5.2 Nos sub-workflows `n8n/tools/*.json`

Abra cada ferramenta e confirme os nós `executeQuery` / `insert` / `update`:

| Ferramenta | Operação principal |
|---|---|
| `tool-list-services` | `SELECT id, name, description, duration_minutes, price FROM services WHERE active = true ORDER BY id` |
| `tool-available-slots` | Consulta `working_hours` e `appointments` ativos da data; nó Code calcula os slots e remove horários passados. |
| `tool-book-appointment` | Upsert em `clients`; valida expediente; insert em `appointments` com `calendar_sync_status='pending'`; erro da exclusão gist vira `reason: "conflito"`. |
| `tool-reschedule-appointment` | Valida antecedência e disponibilidade; `UPDATE` de `start_at/end_at/status`; força `calendar_sync_status='pending'`. |
| `tool-cancel-appointment` | Valida antecedência; `UPDATE status='cancelled', calendar_sync_status='pending'`; grava motivo. |
| `tool-my-appointments` | `SELECT ... JOIN services WHERE client_id = (SELECT id FROM clients WHERE wa_id = $1) ORDER BY start_at DESC LIMIT 20`. |

### 5.3 No workflow de sincronização

- **Buscar Agendamentos Pendentes**: `WHERE calendar_sync_status IN ('pending','failed') AND calendar_sync_attempts < 5`.
- **Marcar Sincronizado** e **Marcar Falha**: `UPDATE` de `calendar_sync_status`, `calendar_event_id`, `calendar_sync_attempts`.

Para cada nó: **Credential to connect with** → selecione `Postgres Barbearia` (ou crie nova conforme o documento [05](05-credenciais-e-segredos.md)). Teste a query em um nó qualquer: deve retornar linha válida ou vazio, sem erro de conexão.

---

## 6. Configurar o workflow de sincronização com o Google Calendar

1. Abra `workflow-calendar-sync.json`.
2. No nó **Criar Evento Google Calendar** (`n8n-nodes-base.googleCalendar`, operation `create`):
   - Credential: **`Google Calendar OAuth`** (criação em [05](05-credenciais-e-segredos.md#5-credencial-google-calendar-oauth));
   - Campo **Calendar ID**: substitua o placeholder `__GOOGLE_CALENDAR_ID__` pelo ID do calendário (ex.: `seu-estabelecimento@gmail.com` ou endereço `...@group.calendar.google.com` copiado das configurações do Google Calendar);
   - `summary` no padrão `{serviço} - {nome}`; `description` com barbeiro e telefone; `start`/`end` em ISO 8601 vindos do agendamento.
3. Conferir os demais nós e suas credenciais (todos os `postgres` usam **`Postgres Barbearia`**):

| Nó (nome exato no JSON) | Tipo | Ação de configuração |
|---|---|---|
| **Cron Verificar Pendências** | `n8n-nodes-base.cron` | Mantê-lo a cada 1 minuto; não altere o intervalo sem motivo. |
| **Buscar Agendamentos Pendentes** | `n8n-nodes-base.postgres` | Credencial `Postgres Barbearia`; query `WHERE calendar_sync_status IN ('pending','failed') AND calendar_sync_attempts < 5`. |
| **Sincronizou?** | `n8n-nodes-base.if` | Verifica se o nó do Google retornou `id` de evento; não exige credencial. |
| **Preparar IDs de Sincronização** | `n8n-nodes-base.code` | Monta `calendar_event_id` para o UPDATE de sucesso. |
| **Marcar Sincronizado** | `n8n-nodes-base.postgres` | Credencial `Postgres Barbearia`. |
| **Marcar Falha** | `n8n-nodes-base.postgres` | Credencial `Postgres Barbearia`; incrementa `calendar_sync_attempts` (máx. 5). |
| **Buscar Cancelados com Evento** | `n8n-nodes-base.postgres` | Lista `status='cancelled'` com `calendar_event_id` preenchido. |
| **Remover Evento do Google** | `n8n-nodes-base.googleCalendar` (operation `delete`) | Credencial `Google Calendar OAuth`; remove o evento no calendário. |
| **Limpar ID do Evento** | `n8n-nodes-base.postgres` | Zera `calendar_event_id` após a remoção. |

4. Salve o workflow.

---

## 7. Ativar os workflows e entender webhook de teste × produção

### 7.1 Quem deve ficar ativo

| Workflow | Ativar? |
|---|---|
| Seis sub-workflows de `n8n/tools/` | **Não** (são chamados por referência). |
| `workflow-calendar-sync.json` | **Sim** (cron só executa com workflow ativo). |
| `workflow-barbearia-whatsapp.json` | **Sim** (webhook de produção só ouve com workflow ativo). |

No canto inferior direito de cada workflow há o interruptor **Active** (ativar/desativar). Após ativar, salve novamente se o n8n pedir.

### 7.2 Webhook de teste (test URL) × webhook de produção (production URL)

| Aspecto | Webhook de teste | Webhook de produção |
|---|---|---|
| Quando existe | Ao clicar em **Test workflow / Execute workflow** com o nó webhook ouvindo | Somente com o workflow **ativo** |
| URL | `/webhook-test/<hash>` temporária | `/webhook/whatsapp/incoming` (caminho fixo do nó **Webhook Recebimento WhatsApp**) |
| Duração | Morre quando a sessão de teste encerra | Persistente enquanto o workflow estiver ativo |
| Uso na ponte | Não usar | Este é o valor de `N8N_WEBHOOK_URL` em `bridge/.env` |

A URL final esperada pela ponte é:

```
http://localhost:5678/webhook/whatsapp/incoming
```

> Se o workflow principal estiver inativo, mensagens da ponte baterão em um webhook inexistente e cairão na mensagem de instabilidade descrita em [03](03-ponte-baileys-whatsapp.md#9-solução-de-problemas-comuns).

---

## 8. Campos esperados no webhook de entrada (§2.1)

O nó **Normalizar Mensagem** (`n8n-nodes-base.set`) mapeia o JSON enviado pela ponte. A tabela abaixo é o contrato exato (§2.1 do `spec/contrato-compartilhado.md`):

| Campo do payload | Tipo | Exemplo | Uso no workflow |
|---|---|---|---|
| `provider` | string | `"baileys"` | Identifica a origem; versão futura `"meta"`; não há lógica de branching por provider nesta versão. |
| `wa_id` | string | `"5511999990000"` | Chave de `conversation_state.wa_id`; usado em todas as ferramentas (`book_appointment`, `get_my_appointments`, etc.). |
| `sender_name` | string | `"Cliente Exemplo"` | Nome sugerido para upsert em `clients.name` quando ausente. |
| `message_id` | string | `"BAILEYS_MSG_ID_ABC123"` | Rastreabilidade de log; não é chave de tabela. |
| `message_type` | string | `"text"` | `text` segue para o agente; demais tipos são avisados pela ponte como "só entendo texto". |
| `message_text` | string | `"quero agendar um corte de cabelo"` | Conteúdo enviado ao Agente Gemini. |
| `timestamp` | number (epoch ms) | `1731100000000` | Ordenação e diagnóstico; não usado como critério de horário passado (quem calcula é a ferramenta). |

Exemplo de requisição (copiável para testes manuais pelo Insomnia/Postman/curl):

```bash
curl -X POST http://localhost:5678/webhook/whatsapp/incoming \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "baileys",
    "wa_id": "5511999990000",
    "sender_name": "Cliente Exemplo",
    "message_id": "BAILEYS_MSG_ID_ABC123",
    "message_type": "text",
    "message_text": "quero agendar um corte de cabelo",
    "timestamp": 1731100000000
  }'
```

A resposta esperada é o §2.2:

```json
{
  "messages": [
    { "to": "5511999990000", "type": "text", "text": "..." }
  ],
  "human_handoff": false
}
```

---

## 9. Acompanhar execuções (Executions list)

No menu lateral **Executions** (Execuções), cada acionamento do webhook e cada chamada de ferramenta geram um registro:

1. **Status verde (success):** fluxo completo; clique para ver os dados de cada nó e confirmar qual ferramenta foi chamada.
2. **Status vermelho (error):** clique na execução e leia o nó em vermelho:
   - Erro de credencial Postgres → revisar §5 e [05](05-credenciais-e-segredos.md);
   - Erro de Gemini → revisar `Google Gemini API` e o modelo `gemini-2.0-flash`;
   - Ferramenta não encontrada → o placeholder da §4 não foi substituído;
   - Erro de Google Calendar → revisar §6; o agendamento segue `pending`/`failed` no banco e **não é perdido**.
3. Filtre por workflow usando o seletor superior; no workflow principal, a execução só aparece quando o webhook de produção recebe uma mensagem (ou no modo teste).

---

## 10. Erros comuns de importação

| Sintoma ao importar | Causa | Solução |
|---|---|---|
| "Workflow could not be imported" / JSON inválido | Arquivo corrompido ou copiado fora da pasta | Reobter o arquivo em `n8n/`; validar que é JSON (deve começar com `{` e terminar com `}`). |
| Nó de ferramenta aponta para workflow inexistente | Placeholder `__TOOL_..._ID__` não preenchido | Voltar na §4 e colar os IDs dos sub-workflows. |
| Tudo salva, mas ao executar dá "no credential" | Nó PostgreSQL/Google/Gemini sem credencial selecionada | Configurar conforme [05](05-credenciais-e-segredos.md) e §5/§6 acima. |
| Mensagem chega na ponte mas o n8n não registra execução | Workflow principal inativo (webhook de produção fora) | Ativar o workflow e conferir a URL em `bridge/.env`. |
| Cron de sincronização não roda | `workflow-calendar-sync.json` inativo | Ativar; o disparo cron só existe em workflows ativos. |
| Execução da ferramenta retorna vazio indevidamente | `seed.sql` não aplicado ou serviços inativos | Conferir tabelas `services` e `working_hours` (§6.3 de [02](02-instalacao-docker-desktop.md#63-conferência-rápida)). |

Próxima etapa: [05 — Credenciais e segredos](05-credenciais-e-segredos.md).
