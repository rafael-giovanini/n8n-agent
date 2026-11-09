-- ============================================================================
-- schema.sql — Banco de dados da Barbearia (PostgreSQL 15+)
-- Projeto: Agente de Atendimento de Barbearia no WhatsApp / n8n
-- Idioma: português brasileiro (pt-BR)
--
-- Como aplicar (na raiz do projeto, após subir o serviço `db` no docker-compose):
--   1) psql -U barb_user -d barbearia -f database/schema.sql
--   2) psql -U barb_user -d barbearia -f database/seed.sql
--
-- Observações:
--   * Usamos o schema padrão `public` para manter compatibilidade total com o
--     nó `Postgres` do n8n (não há schema personalizado nas queries do n8n).
--   * A extensão `btree_gist` é obrigatória para a restrição de exclusão
--     anti-conflito de agendamentos (operador `=` com GiST em inteiros).
-- ============================================================================

-- Extensão que habilita operadores GiST para tipos escalares (inteiro, texto).
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ----------------------------------------------------------------------------
-- Tabela: barbers — Cadastro dos barbeiros da barbearia
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS barbers (
    id          SERIAL PRIMARY KEY,
    name        TEXT NOT NULL,
    specialty   TEXT,
    phone       TEXT,
    active      BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE  barbers              IS 'Cadastro dos barbeiros que atendem na barbearia; inativos são desligados sem exclusão física.';
COMMENT ON COLUMN barbers.id           IS 'Identificador sequencial do barbeiro (chave primária).';
COMMENT ON COLUMN barbers.name         IS 'Nome completo do barbeiro.';
COMMENT ON COLUMN barbers.specialty    IS 'Especialidade do barbeiro (ex.: cortes tradicionais, degradê, infantil).';
COMMENT ON COLUMN barbers.phone        IS 'Telefone de contato interno do barbeiro.';
COMMENT ON COLUMN barbers.active       IS 'Indica se o barbeiro está ativo para novos agendamentos.';
COMMENT ON COLUMN barbers.created_at   IS 'Data e hora (com fuso) de cadastro do registro.';

-- ----------------------------------------------------------------------------
-- Tabela: services — Catálogo de serviços oferecidos
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS services (
    id                 SERIAL PRIMARY KEY,
    name               TEXT NOT NULL,
    description        TEXT,
    duration_minutes   INTEGER NOT NULL CHECK (duration_minutes > 0),
    price              NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    active             BOOLEAN NOT NULL DEFAULT true,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE  services                    IS 'Catálogo de serviços prestados (corte, barba, combo etc.); preço e duração vêm sempre desta tabela, nunca do modelo de linguagem.';
COMMENT ON COLUMN services.id                 IS 'Identificador sequencial do serviço (chave primária).';
COMMENT ON COLUMN services.name              IS 'Nome comercial do serviço exibido ao cliente.';
COMMENT ON COLUMN services.description       IS 'Descrição breve do serviço para a conversa no WhatsApp.';
COMMENT ON COLUMN services.duration_minutes  IS 'Duração do atendimento em minutos; define o fim do agendamento (start_at + duration).';
COMMENT ON COLUMN services.price             IS 'Preço em reais com até duas casas decimais; nunca negativo.';
COMMENT ON COLUMN services.active            IS 'Se o serviço está disponível para agendamento.';
COMMENT ON COLUMN services.created_at        IS 'Data e hora (com fuso) de cadastro do registro.';

-- ----------------------------------------------------------------------------
-- Tabela: clients — Clientes identificados pelo número do WhatsApp (wa_id)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS clients (
    id          SERIAL PRIMARY KEY,
    wa_id       TEXT NOT NULL UNIQUE,
    name        TEXT,
    phone       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE  clients            IS 'Clientes da barbearia; o identificador natural é o wa_id (número internacional sem @s.whatsapp.net).';
COMMENT ON COLUMN clients.id         IS 'Identificador sequencial do cliente (chave primária).';
COMMENT ON COLUMN clients.wa_id       IS 'Número do WhatsApp no formato internacional (ex.: 5511999990000); único por cliente.';
COMMENT ON COLUMN clients.name        IS 'Nome informado pelo cliente na conversa (pode ser preenchido gradualmente).';
COMMENT ON COLUMN clients.phone       IS 'Telefone adicional informado pelo cliente, quando existente.';
COMMENT ON COLUMN clients.created_at  IS 'Data e hora (com fuso) do primeiro contato.';
COMMENT ON COLUMN clients.updated_at  IS 'Data e hora (com fuso) da última atualização do cadastro.';

-- ----------------------------------------------------------------------------
-- Tabela: working_hours — Expediente semanal (0 = domingo … 6 = sábado)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS working_hours (
    id                   SERIAL PRIMARY KEY,
    day_of_week          SMALLINT NOT NULL UNIQUE CHECK (day_of_week BETWEEN 0 AND 6),
    closed               BOOLEAN NOT NULL DEFAULT false,
    open_time            TIME,
    close_time           TIME,
    break_start          TIME,
    break_end            TIME,
    slot_interval_minutes INTEGER NOT NULL DEFAULT 30 CHECK (slot_interval_minutes > 0)
);

COMMENT ON TABLE  working_hours                       IS 'Expediente de funcionamento por dia da semana; usado pela ferramenta de disponibilidade de horários.';
COMMENT ON COLUMN working_hours.id                    IS 'Identificador sequencial da linha de expediente.';
COMMENT ON COLUMN working_hours.day_of_week          IS 'Dia da semana: 0 = domingo, 1 = segunda-feira, …, 6 = sábado.';
COMMENT ON COLUMN working_hours.closed               IS 'true quando a barbearia fecha neste dia (horários nulos).';
COMMENT ON COLUMN working_hours.open_time             IS 'Horário de abertura no dia (HH:MM), nulo quando fechado.';
COMMENT ON COLUMN working_hours.close_time            IS 'Horário de fechamento no dia (HH:MM), nulo quando fechado.';
COMMENT ON COLUMN working_hours.break_start           IS 'Início do intervalo de almoço (HH:MM); nenhum slot pode começar/transpor este intervalo.';
COMMENT ON COLUMN working_hours.break_end             IS 'Fim do intervalo de almoço (HH:MM).';
COMMENT ON COLUMN working_hours.slot_interval_minutes IS 'Granularidade dos horários oferecidos (em minutos); padrão 30.';

-- ----------------------------------------------------------------------------
-- Tabela: appointments — Agendamentos (carência central do sistema)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS appointments (
    id                    SERIAL PRIMARY KEY,
    client_id             INTEGER NOT NULL REFERENCES clients(id),
    service_id            INTEGER NOT NULL REFERENCES services(id),
    barber_id             INTEGER REFERENCES barbers(id),
    start_at              TIMESTAMPTZ NOT NULL,
    end_at                TIMESTAMPTZ NOT NULL,
    status                TEXT NOT NULL DEFAULT 'scheduled'
                          CHECK (status IN ('scheduled','confirmed','cancelled','completed','no_show')),
    calendar_event_id     TEXT,
    calendar_sync_status  TEXT NOT NULL DEFAULT 'pending'
                          CHECK (calendar_sync_status IN ('pending','synced','failed')),
    calendar_sync_attempts INTEGER NOT NULL DEFAULT 0,
    note                  TEXT,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (end_at > start_at),
    -- Exclusão anti-conflito: dois atendimentos ativos (scheduled/confirmed) não
    -- podem se sobrepor para o mesmo barbeiro. Agendamentos sem barbeiro
    -- (barber_id NULL) são normalizados para 0 via COALESCE, conforme §3 do
    -- contrato, para que a regra do GiST continue funcionando.
    EXCLUDE USING gist (
        COALESCE(barber_id, 0) WITH =,
        tstzrange(start_at, end_at, '[)') WITH &&
    ) WHERE (status IN ('scheduled','confirmed'))
);

COMMENT ON TABLE  appointments                     IS 'Agendamentos dos clientes; a exclusão GiST impede sobreposição de atendimentos ativos por barbeiro.';
COMMENT ON COLUMN appointments.id                  IS 'Identificador sequencial do agendamento (chave primária).';
COMMENT ON COLUMN appointments.client_id           IS 'Cliente agendado (obrigatório); relação com clients.id.';
COMMENT ON COLUMN appointments.service_id          IS 'Serviço agendado (obrigatório); relação com services.id.';
COMMENT ON COLUMN appointments.barber_id           IS 'Barbeiro escolhido (opcional); nulo quando ainda não houver preferência.';
COMMENT ON COLUMN appointments.start_at           IS 'Início do atendimento com fuso horário (ISO 8601 com offset).';
COMMENT ON COLUMN appointments.end_at              IS 'Fim do atendimento; igual a start_at + duração do serviço.';
COMMENT ON COLUMN appointments.status              IS 'Situação do agendamento: scheduled, confirmed, cancelled, completed ou no_show.';
COMMENT ON COLUMN appointments.calendar_event_id   IS 'ID do evento criado no Google Calendar; nulo enquanto não sincronizado.';
COMMENT ON COLUMN appointments.calendar_sync_status IS 'Status da sincronização com o Google Calendar: pending, synced ou failed.';
COMMENT ON COLUMN appointments.calendar_sync_attempts IS 'Número de tentativas de sincronização; workflow de sync desiste após 5 tentativas.';
COMMENT ON COLUMN appointments.note                IS 'Observações livres da conversa ou motivo do cancelamento.';
COMMENT ON COLUMN appointments.created_at          IS 'Data e hora (com fuso) de criação do registro.';
COMMENT ON COLUMN appointments.updated_at         IS 'Data e hora (com fuso) da última alteração.';

-- ----------------------------------------------------------------------------
-- Tabela: conversation_state — Estado da conversa por número de WhatsApp
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS conversation_state (
    wa_id         TEXT PRIMARY KEY,
    client_id     INTEGER REFERENCES clients(id),
    state_data    JSONB NOT NULL DEFAULT '{}'::jsonb,
    last_intent   TEXT,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE  conversation_state            IS 'Memória curta da conversa com cada número do WhatsApp; carregada no início do fluxo e gravada ao final.';
COMMENT ON COLUMN conversation_state.wa_id       IS 'Número do WhatsApp do cliente; chave primária da tabela.';
COMMENT ON COLUMN conversation_state.client_id  IS 'Cliente vinculado após identificação; relação com clients.id.';
COMMENT ON COLUMN conversation_state.state_data IS 'Objeto JSONB com dados coletados no diálogo (serviço, data sugerida, barbeiro etc.).';
COMMENT ON COLUMN conversation_state.last_intent IS 'Última intenção reconhecida na conversa, para dar continuidade ao assunto.';
COMMENT ON COLUMN conversation_state.updated_at  IS 'Data e hora (com fuso) da última interação registrada.';

-- ----------------------------------------------------------------------------
-- Tabela: human_tickets — Pendências transferidas para atendente humano
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS human_tickets (
    id          SERIAL PRIMARY KEY,
    wa_id       TEXT NOT NULL,
    client_id   INTEGER REFERENCES clients(id),
    name        TEXT,
    reason      TEXT,
    status      TEXT NOT NULL DEFAULT 'open'
                CHECK (status IN ('open','in_progress','resolved')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE  human_tickets            IS 'Chamados abertos quando o atendimento automático não resolve (erro, pedido de atendente, assunto sensível).';
COMMENT ON COLUMN human_tickets.id         IS 'Identificador sequencial do chamado (chave primária).';
COMMENT ON COLUMN human_tickets.wa_id      IS 'Número do WhatsApp que originou a transferência.';
COMMENT ON COLUMN human_tickets.client_id  IS 'Cliente vinculado, quando já cadastrado; relação com clients.id.';
COMMENT ON COLUMN human_tickets.name       IS 'Nome informado pelo cliente no momento da transferência.';
COMMENT ON COLUMN human_tickets.reason    IS 'Motivo da abertura do chamado (erro do agente, solicitação de humano, etc.).';
COMMENT ON COLUMN human_tickets.status    IS 'Andamento do chamado: open, in_progress ou resolved.';
COMMENT ON COLUMN human_tickets.created_at IS 'Data e hora (com fuso) de abertura do chamado.';
COMMENT ON COLUMN human_tickets.updated_at IS 'Data e hora (com fuso) da última movimentação.';

-- ----------------------------------------------------------------------------
-- Índices (§3.2 do contrato)
-- ----------------------------------------------------------------------------
-- Agendamentos por cliente ordenados por data (ferramenta get_my_appointments).
CREATE INDEX IF NOT EXISTS idx_appointments_client_start
    ON appointments (client_id, start_at);

-- Filtro do workflow de sincronização: status do agendamento + status do sync.
CREATE INDEX IF NOT EXISTS idx_appointments_status_sync
    ON appointments (status, calendar_sync_status);

-- Consulta de estado de conversa mais recente por atualização.
CREATE INDEX IF NOT EXISTS idx_conversation_state_updated
    ON conversation_state (updated_at);
