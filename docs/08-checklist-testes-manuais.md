# 08 — Checklist de testes manuais

> **Sumário**
>
> 1. [Pré-condições antes de começar](#1-pré-condições-antes-de-começar)
> 2. [Como preencher este checklist](#2-como-preencher-este-checklist)
> 3. [Checklist numerado (esperado × resultado)](#3-checklist-numerado-esperado--resultado)
> 4. [Consultas SQL úteis durante os testes](#4-consultas-sql-úteis-durante-os-testes)
> 5. [Critério de entrega e assinatura](#5-critério-de-entrega-e-assinatura)

---

## 1. Pré-condições antes de começar

| # | Item obrigatório | Verificado em |
|---|---|---|
| P1 | `db` e `n8n` com `healthy` em `docker compose ps` | [02](02-instalacao-docker-desktop.md) |
| P2 | `schema.sql` e `seed.sql` aplicados (3 serviços, 2 barbeiros, expediente ter–sáb 09–19) | [02](02-instalacao-docker-desktop.md#6-aplicar-os-arquivos-sql-schema-e-seed) |
| P3 | Seis sub-workflows importados e nós `toolWorkflow` apontados; credencial `Postgres Barbearia` nos nós SQL | [04](04-importacao-workflow-n8n.md) |
| P4 | `workflow-calendar-sync.json` e `workflow-barbearia-whatsapp.json` **ativos** | [04](04-importacao-workflow-n8n.md#7-ativar-os-workflows-e-entender-webhook-de-teste--produção) |
| P5 | Credenciais `Google Gemini API` e `Google Calendar OAuth` configuradas; `GOOGLE_CALENDAR_ID` preenchido | [05](05-credenciais-e-segredos.md) |
| P6 | Ponte Baileys conectada (`GET http://localhost:3000/health` → `connected: true`) | [03](03-ponte-baileys-whatsapp.md) |
| P7 | Prompt de `config/agent-prompt.md` colado no nó **Agente Gemini (Ferramentas)** | [07](07-prompt-e-regras-de-dialogo.md) |
| P8 | iPhone/Mac com a assinatura do calendário feita (para o teste 8) | [06](06-sincronizacao-apple-calendar.md) |

Use dois números de teste quando possível: um cliente simulado e o número da ponte. Anote o `wa_id` de teste (formato internacional, ex.: `5511999990000`).

---

## 2. Como preencher este checklist

- **Resultado**: marque `OK` quando o esperado acontecer exatamente; marque `FALHO` caso contrário.
- **Observações**: anote data/hora, mensagem exativa enviada, ID da execução no n8n, `appointment_id` retornado e qualquer comportamento fora do previsto.
- Um `FALHO` deve ser corrigido e re-testado antes de seguir para os cenários dependentes (ex.: agendamento só faz sentido após boas-vindas e catálogo funcionarem).

---

## 3. Checklist numerado (esperado × resultado)

| # | Cenário | Ação de teste | Resultado esperado | Resultado (OK/FALHO) | Observações |
|---|---|---|---|---|---|
| 1 | Boas-vindas | Enviar "oi" / "olá" para o número da ponte | Bia se apresenta (identidade da seção 1 do prompt), em pt-BR, tom amigável e mensagem curta; não inventa preços ainda; execução verde no n8n. | ☐ OK ☐ FALHO | |
| 2 | Listar serviços e preços | Perguntar "quais serviços vocês têm?" / "preços" | `list_services` é chamada; resposta lista os 3 serviços do seed com **nome, duração e preço vindos da ferramenta**: Corte de cabelo 30 min R$ 35,00; Barba completa 30 min R$ 25,00; Combo cabelo + barba 60 min R$ 55,00. | ☐ OK ☐ FALHO | |
| 3 | Pedir horário em segunda-feira (fechado) | Pedir um corte para a próxima segunda-feira | `get_available_slots` retorna `closed: true`; Bia informa que a barbearia fecha às segundas (motivo vindo da ferramenta) e sugere outro dia; **não** oferece horário falso. | ☐ OK ☐ FALHO | |
| 4 | Horário passado recusado | Pedir horário anterior ao momento atual (ex.: "ontem às 18h" ou "hoje cedo") | A ferramenta não oferece slots passados; Bia explica que só agenda horários futuros e oferece opções do dia seguinte/expediente. | ☐ OK ☐ FALHO | |
| 5 | Conflito de horário recusado | Com dois números/clientes (ou duas tentativas), reservar o mesmo horário/serviço/barbeiro duas vezes | A segunda chamada de `book_appointment` retorna `ok: false, reason: "conflito"` (exclusão gist); Bia oferece próximos horários disponíveis; não grava segunda linha sobreposta. | ☐ OK ☐ FALHO | |
| 6 | Agendamento com sucesso e comprovante | Seguir a ordem: nome → serviço (ex.: Corte de cabelo) → data futura em dia aberto → horário oferecido → barbeiro (ou "qualquer") | `book_appointment` retorna `ok: true` com `appointment_id`, `start_at` e `end_at`; Bia envia comprovante com nome, serviço, data/hora, barbeiro, duração e valor; linha em `appointments` com `status='scheduled'` e `calendar_sync_status='pending'`. | ☐ OK ☐ FALHO | |
| 7 | Evento aparece no Google Calendar | Após o teste 6, aguardar até 1–2 minutos e abrir o calendário configurado | Workflow cron cria o evento (summary `{serviço} - {nome}`, description com barbeiro e telefone); status no banco muda para `synced` com `calendar_event_id` preenchido. | ☐ OK ☐ FALHO | |
| 8 | Evento aparece no Apple Calendar | Com a assinatura CalDAV/ICS já feita (P8), abrir o app Calendário no iPhone/Mac | O mesmo evento aparece no calendário assinado, no fuso e horário corretos; edição pelo Apple não altera o sistema (leitura). | ☐ OK ☐ FALHO | |
| 9 | Reagendamento | Pedir para mudar o agendamento do teste 6 para outro horário livre no mesmo dia ou outro dia | `reschedule_appointment` valida disponibilidade e antecedência; retorno `ok: true`; `start_at/end_at` atualizados; `calendar_sync_status` volta para `pending` e o cron atualiza/recria o evento no Google Calendar. | ☐ OK ☐ FALHO | |
| 10a | Cancelamento **dentro** da antecedência de 2h | Agendar um horário com mais de 2h de antecedência e pedir cancelamento | `cancel_appointment` retorna `ok: true, policy_violation: false`; status `cancelled`; evento removido do Google Calendar pela rama de cancelados; Bia confirma o cancelamento. | ☐ OK ☐ FALHO | |
| 10b | Cancelamento **fora** da antecedência de 2h | Tentar cancelar horário com menos de 2h para o início (use um agendamento de teste curto ou ajuste `CANCEL_MIN_HOURS` em homologação) | Retorno `ok: false, policy_violation: true, reason: "Cancelamento exige 2h de antecedência"`; status continua `scheduled`; Bia não confirma exclusão e oferece falar com atendente. | ☐ OK ☐ FALHO | |
| 11 | Consultar "meus agendamentos" | Enviar "quais são meus agendamentos?" / "meus horários" | `get_my_appointments` retorna a lista do `wa_id` (JOIN com `services`, ordenada por data); Bia lista serviço, data/hora e status; não mostra agendamentos de outros números. | ☐ OK ☐ FALHO | |
| 12 | Transferência para atendente | Enviar "atendente" (também testar "falar com alguém" e "pessoa" se houver tempo) | Ticket inserido em `human_tickets` com `wa_id`, motivo e `status='open'`; resposta com `human_handoff: true`; Bia informa que um atendente será avisado e encerra o fluxo automático. | ☐ OK ☐ FALHO | |
| 13 | Falha do Google Calendar não perde o agendamento | Simular indisponibilidade do Google (ex.: revogar temporariamente o token da credencial `Google Calendar OAuth` ou desconectar a rede do Google) e realizar novo agendamento | `book_appointment` grava normalmente com `calendar_sync_status='pending'`; cron marca `failed` e incrementa `calendar_sync_attempts` (máx. 5); ao restaurar a credencial, o retry cria o evento; **nenhum agendamento é perdido**. | ☐ OK ☐ FALHO | |
| 14 | Reinício da ponte mantém estado da conversa | Com uma conversa em andamento (ex.: cliente já deu o nome mas ainda não escolheu serviço), interrompa `npm start` com `Ctrl + C`, suba novamente com `npm start`, e continue a mensagem | Sessão do WhatsApp restaurada de `bridge/session/` (não pede QR/pair code de novo); `conversation_state` no PostgreSQL mantém `state_data` e `last_intent`; Bia continua de onde parou. | ☐ OK ☐ FALHO | |

---

## 4. Consultas SQL úteis durante os testes

Executar pelo terminal do projeto (serviço `db`; nome do contêiner `barbearia-db`). Ajustar usuário/banco conforme `.env`; no PowerShell use `docker compose exec -T`:

```bash
docker compose exec -T db psql -U barb_user -d barbearia -c "SELECT id, client_id, service_id, barber_id, start_at, end_at, status, calendar_sync_status, calendar_event_id, calendar_sync_attempts FROM appointments ORDER BY id DESC LIMIT 10;"
```

```bash
docker compose exec -T db psql -U barb_user -d barbearia -c "SELECT wa_id, client_id, last_intent, updated_at FROM conversation_state ORDER BY updated_at DESC LIMIT 10;"
```

```bash
docker compose exec -T db psql -U barb_user -d barbearia -c "SELECT id, wa_id, name, reason, status, created_at FROM human_tickets ORDER BY id DESC LIMIT 10;"
```

```bash
docker compose exec -T db psql -U barb_user -d barbearia -c "SELECT c.wa_id, s.name AS servico, a.start_at, a.status FROM appointments a JOIN clients c ON c.id=a.client_id JOIN services s ON s.id=a.service_id ORDER BY a.start_at DESC LIMIT 10;"
```

Outras verificações rápidas:

- **Ponte:** `curl http://localhost:3000/health` → `{ "status": "ok", "connected": true }`.
- **Execuções do n8n:** menu **Executions**; verificar sucesso nos cenários 1–12 e falha controlada no 13.
- **Google Calendar web:** conferir criação (7), atualização (9) e remoção (10a).
- **Apple Calendar:** conferir leitura (8) e atraso de cache (documento [06](06-sincronizacao-apple-calendar.md#6-solução-de-problemas)).

---

## 5. Critério de entrega e assinatura

- Todos os itens **1 a 14** devem estar `OK` antes de usar o número com clientes reais.
- Itens `FALHO` devem ter causa registrada em Observações, correção aplicada e novo resultado.
- Itens dependentes (6→7→8; 9; 10a) não devem ser aprovados se o antecedente falhar.

| Responsável pelos testes | Data | Total de OK / total de itens | Observação geral |
|---|---|---|---|
|  |  | 14 / 14 |  |

> Lembrete final: antes de expor o número real, revise os riscos do Baileys e o plano de migração em [09-riscos-e-migracao-meta-cloud-api.md](09-riscos-e-migracao-meta-cloud-api.md).
