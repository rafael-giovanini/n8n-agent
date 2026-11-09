# Agente de Atendimento de Barbearia no WhatsApp (n8n + Gemini)

> **Sumário**
>
> 1. [Visão geral da solução](#1-visão-geral-da-solução)
> 2. [Aviso obrigatório — risco de banimento do número](#2-aviso-obrigatório--risco-de-banimento-do-número)
> 3. [Stack tecnológica](#3-stack-tecnológica)
> 4. [Pré-requisitos](#4-pré-requisitos)
> 5. [Ordem de execução do setup (8 passos)](#5-ordem-de-execução-do-setup-8-passos)
> 6. [Árvore de arquivos do projeto](#6-árvore-de-arquivos-do-projeto)
> 7. [Documentação (pasta `docs/`)](#7-documentação-pasta-docs)
> 8. [Resumo das credenciais](#8-resumo-das-credenciais)

---

## 1. Visão geral da solução

Esta solução coloca no WhatsApp de uma barbearia uma **atendente virtual chamada Bia**, que conversa em português brasileiro, tira dúvidas de serviços e preços, verifica horários disponíveis e **agenda, reage e cancela horários automaticamente**. A regra de negócio não fica "na cabeça" do modelo de IA: o agente usa seis ferramentas (`list_services`, `get_available_slots`, `book_appointment`, `reschedule_appointment`, `cancel_appointment`, `get_my_appointments`) que consultam e gravam um banco PostgreSQL; os agendamentos confirmados são espelhados no Google Calendar por um workflow de sincronização, e o calendário público do Google é assinado no Apple Calendar (iPhone/Mac) apenas como leitura.

O fluxo é orquestrado pelo **n8n** (plataforma de automação visual, hospedada localmente via Docker):

1. O cliente manda uma mensagem no WhatsApp.
2. A **ponte Baileys** (`bridge/`) recebe a mensagem e a converte num **payload neutro** (contrato §2 do `spec/contrato-compartilhado.md`) enviado por webhook ao n8n.
3. O workflow principal normaliza a mensagem, carrega o estado da conversa no PostgreSQL e chama o **Agente Gemini**, que escolhe as ferramentas necessárias.
4. As ferramentas (sub-workflows em `n8n/tools/`) verificam preços, horários e gravam o agendamento com `calendar_sync_status='pending'`.
5. O workflow `workflow-calendar-sync.json` (cron a cada 1 minuto) pega os pendentes, cria/atualiza/remove eventos no Google Calendar e marca `synced` ou `failed`.
6. Se o cliente pedir um atendente humano (palavras-chave como `atendente`), a conversa é registrada em `human_tickets` e a ponte envia a mensagem de transferência com `human_handoff: true`.

Princípio central: **a ponte de WhatsApp é apenas transporte**. O n8n nunca conhece detalhes da biblioteca Baileys; tudo que entra e sai usa o payload neutro. Por isso, no futuro a ponte poderá ser substituída pela Meta WhatsApp Cloud API **sem alterar os workflows, o banco ou o prompt** (ver [docs/09](docs/09-riscos-e-migracao-meta-cloud-api.md)).

---

## 2. Aviso obrigatório — risco de banimento do número

> **ATENÇÃO — LEIA ANTES DE USAR NÚMERO REAL DA BARBEARIA**
>
> A conexão com o WhatsApp nesta versão usa a biblioteca **Baileys**, que é uma **implementação não oficial** do protocolo WhatsApp Web. Ela **não é autorizada pela Meta e viola os Termos de Serviço do WhatsApp/Meta**. Consequências possíveis:
>
> - **Bloqueio total ou temporário do número** no WhatsApp, sem aviso prévio e sem prazo para recuperar;
> - Sem SLA, sem suporte oficial e sem garantia de funcionamento após atualizações do WhatsApp;
> - Banimento do chip/celular usado na sessão, especialmente se o número enviar muitas mensagens ou mensagens não solicitadas.
>
> **Mitigações recomendadas (obrigatórias em produção):**
>
> 1. Use um **número comercial secundário** exclusivo para a ponte; nunca use o número pessoal do dono.
> 2. **Não envie broadcasts, propagandas, promoções em massa ou mensagens para quem não iniciou a conversa.**
> 3. Mantenha **baixa frequência** de mensagens; responda só clientes que escreveram primeiro.
> 4. Monitore o estado da conexão (`GET /health`) e reinicie a ponte apenas quando necessário.
> 5. Tenha um **plano de migração** pronto para a Meta WhatsApp Cloud API (oficial, homologada) — a arquitetura já foi desenhada para isso: substitua somente a pasta `bridge/` por um adaptador `bridge-meta/`.
>
> Detalhes completos dos riscos e do guia de migração oficial em [docs/09-riscos-e-migracao-meta-cloud-api.md](docs/09-riscos-e-migracao-meta-cloud-api.md).

---

## 3. Stack tecnológica

| Camada | Tecnologia | Função neste projeto |
|---|---|---|
| Transporte WhatsApp | **Baileys** (`@whiskeysockets/baileys`, ^6.7.x) | Ponte não oficial que lê e escreve mensagens do WhatsApp Web; expõe `POST /send` e `GET /health`; fica em `bridge/`. **Ver aviso de risco acima.** |
| Runtime da ponte | **Node.js** (com `npm`) | Executa `bridge/server.js`; `"type": "module"`; dependências: Baileys, express, qrcode-terminal, pino. |
| Orquestração / agente | **n8n** (imagem `n8nio/n8n:latest` no Docker) | Workflow principal com webhook, estado da conversa, nó Agente de ferramentas (Tools Agent) e resposta síncrona; sub-workflows de ferramenta; workflow cron de sincronização com o Google Calendar. |
| Banco de dados | **PostgreSQL 15** (`postgres:15-alpine`) | Tabelas `barbers`, `services`, `clients`, `working_hours`, `appointments`, `conversation_state`, `human_tickets`; exclusão anti-conflito por `btree_gist`. |
| Modelo de linguagem | **Google Gemini** (`gemini-2.0-flash`, nó nativo `n8n-nodes-langchain.lmChatGoogleGemini`) | Agente conversacional com function calling das 6 ferramentas; free tier generoso e bom em pt-BR. Alternativa documentada: OpenAI `gpt-4o-mini`. |
| Calendário do negócio | **Google Calendar** (nó `n8n-nodes-base.googleCalendar`, OAuth2) | Recebe os eventos dos agendamentos confirmados; disponibiliza link público ICS/CalDAV. |
| Calendário do celular (leitura) | **Apple Calendar** (iPhone/Mac) | Assinatura somente leitura do calendário público do Google; não cria eventos — os eventos nascem no n8n/PostgreSQL. |
| Empacotamento | **Docker Compose** | Serviços `db` e `n8n`; volumes `pg_data` e `n8n_data`; porta n8n `${N8N_PORT:-5678}`. |

---

## 4. Pré-requisitos

Antes de começar, instale no Windows 10/11:

| Item | Para quê | Observação |
|---|---|---|
| **Docker Desktop** (Windows) | Roda PostgreSQL e n8n em contêineres | Precisa de **WSL2** habilitado; passo a passo em [docs/02](docs/02-instalacao-docker-desktop.md). |
| **Node.js 18+ e npm** | Roda a ponte Baileys em `bridge/` | Baixe em nodejs.org; após instalar, confirme com `node --version` e `npm --version`. |
| **Conta Google** | Chave da Gemini API e credencial OAuth do Google Calendar | A chave gratuita sai no Google AI Studio; o OAuth é criado no Google Cloud Console. |
| **Número de WhatsApp secundário** | Pareamento da ponte (QR Code ou pair code) | **Nunca use seu número pessoal** — ver aviso da §2. |
| Editor de texto | Editar `.env` e colar o prompt | VS Code ou Notepad++ funcionam. |
| (Opcional) Cliente SQL | Aplicar `schema.sql` e `seed.sql` | DBeaver ou Beekeeper Studio; alternativa via `docker exec` — ver [docs/02](docs/02-instalacao-docker-desktop.md). |

> Não é necessário instalar PostgreSQL ou n8n diretamente no Windows: ambos sobem em contêineres pelo Docker Compose.

---

## 5. Ordem de execução do setup (8 passos)

Siga **nesta ordem**. Cada passo remete a um documento detalhado da pasta `docs/`.

| # | Passo | O que fazer | Documento |
|---|---|---|---|
| 1 | **Instalar e iniciar o Docker Desktop** | Instalar Docker Desktop no Windows com WSL2; deixar o ícone do Docker rodando na bandeja. | [docs/02](docs/02-instalacao-docker-desktop.md) |
| 2 | **Subir os contêineres com `docker compose up -d`** | Copiar `.env.example` para `.env`, preencher as variáveis e subir `db` e `n8n`; aguardar os healthchecks e abrir `http://localhost:5678`. | [docs/02](docs/02-instalacao-docker-desktop.md) |
| 3 | **Aplicar o banco: `schema.sql` e `seed.sql`** | Executar `database/schema.sql` (estrutura) e `database/seed.sql` (2 barbeiros, 3 serviços, horários de funcionamento) no PostgreSQL do contêiner `db`. | [docs/02](docs/02-instalacao-docker-desktop.md#6-aplicar-os-arquivos-sql-schema-e-seed) |
| 4 | **Importar os workflows no n8n e criar as credenciais** | Primeiro os 6 sub-workflows de `n8n/tools/`, depois `workflow-calendar-sync.json`, por fim `workflow-barbearia-whatsapp.json`; apontar cada nó `toolWorkflow` para o sub-workflow importado; cadastrar a credencial `Postgres Barbearia`. | [docs/04](docs/04-importacao-workflow-n8n.md) · [docs/05](docs/05-credenciais-e-segredos.md) |
| 5 | **Configurar o Google Calendar OAuth** | Criar projeto no Google Cloud Console, habilitar a Google Calendar API, criar OAuth client ID (Web application), registrar no n8n como `Google Calendar OAuth`, copiar o Calendar ID e preencher `GOOGLE_CALENDAR_ID` no `.env`. | [docs/05](docs/05-credenciais-e-segredos.md) |
| 6 | **Instalar e rodar a ponte Baileys** | `cd bridge`, `npm install`, copiar `bridge/.env.example` para `bridge/.env`, ajustar `OWNER_NUMBER` e `REQUEST_PAIRING_CODE`, rodar `npm start`; parear o número pelo QR Code ou pair code; a sessão fica persistida em `bridge/session/`. | [docs/03](docs/03-ponte-baileys-whatsapp.md) |
| 7 | **Importar/colar o prompt em `config/agent-prompt.md`** | Revisar o prompt em `config/agent-prompt.md`, ajustar os valores de FAQ (endereço, Pix, horários) vindos da configuração, e colar o conteúdo no campo System Message/Prompt do nó **Agente Gemini (Ferramentas)**. | [docs/07](docs/07-prompt-e-regras-de-dialogo.md) |
| 8 | **Testar conforme o checklist manual** | Rodar todos os cenários do checklist (boas-vindas, preços, agendamento, conflitos, reagendamento, cancelamento, transferência, falha de calendário, reinício da ponte). | [docs/08](docs/08-checklist-testes-manuais.md) |

Após os testes, leia o documento de riscos e migração antes de expor o número a clientes reais: [docs/09](docs/09-riscos-e-migracao-meta-cloud-api.md).

---

## 6. Árvore de arquivos do projeto

```
barbearia-whatsapp-n8n/
├── README.md                              # Este arquivo (visão geral e setup)
├── docker-compose.yml                     # Serviços db (PostgreSQL 15) e n8n
├── .env.example                           # Variáveis de ambiente de exemplo da raiz
├── database/
│   ├── schema.sql                         # Estrutura das 7 tabelas (PostgreSQL 15)
│   └── seed.sql                            # Dados de exemplo (barbeiros, serviços, expediente)
├── n8n/
│   ├── workflow-barbearia-whatsapp.json    # Workflow principal (webhook + Agente Gemini)
│   ├── workflow-calendar-sync.json         # Workflow cron de sincronização com Google Calendar
│   └── tools/
│       ├── tool-list-services.json
│       ├── tool-available-slots.json
│       ├── tool-book-appointment.json
│       ├── tool-reschedule-appointment.json
│       ├── tool-cancel-appointment.json
│       └── tool-my-appointments.json
├── bridge/                                 # Ponte Baileys (transporte — substituível)
│   ├── package.json
│   ├── server.js
│   ├── .env.example
│   └── session/
│       └── .gitkeep                        # Sessão pareada persiste aqui (não versionar)
├── config/
│   └── agent-prompt.md                     # Prompt da Bia (System Message do agente)
├── spec/
│   └── contrato-compartilhado.md           # Contrato congelado (payload, tabelas, nomes)
└── docs/
    ├── 01-arquitetura.md
    ├── 02-instalacao-docker-desktop.md
    ├── 03-ponte-baileys-whatsapp.md
    ├── 04-importacao-workflow-n8n.md
    ├── 05-credenciais-e-segredos.md
    ├── 06-sincronizacao-apple-calendar.md
    ├── 07-prompt-e-regras-de-dialogo.md
    ├── 08-checklist-testes-manuais.md
    └── 09-riscos-e-migracao-meta-cloud-api.md
```

> Regra de ouro: não renomeie arquivos, tabelas, ferramentas, nós nem credenciais. Os nomes acima estão fixados no `spec/contrato-compartilhado.md`.

---

## 7. Documentação (pasta `docs/`)

| Documento | Conteúdo principal |
|---|---|
| [01 — Arquitetura](docs/01-arquitetura.md) | Diagrama Mermaid, payload neutro §2, modelo de dados, princípio do adaptador isolado e as seis ferramentas. |
| [02 — Instalação do Docker Desktop](docs/02-instalacao-docker-desktop.md) | Passo a passo Windows (WSL2), compose, healthcheck, criação do administrador do n8n, aplicação dos SQL, comandos úteis. |
| [03 — Ponte Baileys (WhatsApp)](docs/03-ponte-baileys-whatsapp.md) | Instalação da ponte, QR/pair code, endpoints `/send` e `/health`, solução de problemas comuns. |
| [04 — Importação dos workflows no n8n](docs/04-importacao-workflow-n8n.md) | Ordem de importação, apontamento dos `toolWorkflow`, credencial Postgres, webhook de produção vs teste, payload esperado. |
| [05 — Credenciais e segredos](docs/05-credenciais-e-segredos.md) | Gemini API, Postgres Barbearia, Google Calendar OAuth; tabela de variáveis do `.env.example`; regra de não commitar segredos. |
| [06 — Sincronização com Apple Calendar](docs/06-sincronizacao-apple-calendar.md) | Link ICS público do Google, assinatura CalDAV no iPhone e no Mac; limitação somente-leitura; troubleshooting. |
| [07 — Prompt e regras de diálogo](docs/07-prompt-e-regras-de-dialogo.md) | Estrutura de `config/agent-prompt.md`, regras de ouro, política de cancelamento de 2h, palavras-chave de transferência, FAQ. |
| [08 — Checklist de testes manuais](docs/08-checklist-testes-manuais.md) | Cenários de teste com esperado × resultado (OK/FALHO) e espaço de observações. |
| [09 — Riscos e migração para a Meta Cloud API](docs/09-riscos-e-migracao-meta-cloud-api.md) | Riscos do Baileys, mitigações, tabela de equivalência do payload e guia prático de migração oficial. |

---

## 8. Resumo das credenciais

As três credenciais cadastradas dentro do n8n (nomes fixos, detalhes em [docs/05](docs/05-credenciais-e-segredos.md)):

| Nome da credencial no n8n | Tipo nativo | Origem dos dados |
|---|---|---|
| `Postgres Barbearia` | `postgres` | Host `db`, porta `5432`, usuário/senha/banco vindos do `.env` (serviço `db` do compose). |
| `Google Gemini API` | `googleGeminiApi` | API key gratuita do Google AI Studio (`https://aistudio.google.com/`). |
| `Google Calendar OAuth` | `googleCalendarOAuth2Api` | OAuth2 do Google Cloud Console com escopo `https://www.googleapis.com/auth/calendar.events`. |

> **Nunca** commite `.env`, `bridge/.env`, tokens, chaves ou números reais no repositório. Use sempre os placeholders `__EXEMPLO__` nos arquivos versionados.
