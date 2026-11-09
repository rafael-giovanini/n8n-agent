-- ============================================================================
-- seed.sql — Dados de exemplo da barbearia (§3.3 do contrato)
-- Projeto: Agente de Atendimento de Barbearia no WhatsApp / n8n
-- Idioma: português brasileiro (pt-BR)
--
-- Como aplicar (após o schema.sql):
--   psql -U barb_user -d barbearia -f database/schema.sql
--   psql -U barb_user -d barbearia -f database/seed.sql
--
-- Este script é idempotente: pode ser executado várias vezes sem duplicar
-- linhas. Barbeiros e serviços usam WHERE NOT EXISTS por nome; o expediente
-- usa ON CONFLICT (day_of_week) DO NOTHING.
--
-- Conteúdo: 2 barbeiros, 3 serviços, expediente terça–sábado 09h–19h com
-- intervalo de almoço 12h–13h; domingo e segunda fechados.
-- Não há clientes nem agendamentos neste seed.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Barbeiros (2 registros de exemplo)
-- ----------------------------------------------------------------------------
INSERT INTO barbers (name, specialty, phone, active)
SELECT 'Carlos Souza', 'Cortes tradicionais e navalhado', '11000000001', true
WHERE NOT EXISTS (SELECT 1 FROM barbers WHERE name = 'Carlos Souza');

INSERT INTO barbers (name, specialty, phone, active)
SELECT 'Felipe Lima', 'Degradê e infantil', '11000000002', true
WHERE NOT EXISTS (SELECT 1 FROM barbers WHERE name = 'Felipe Lima');

-- ----------------------------------------------------------------------------
-- Serviços (3 registros de exemplo: duração em minutos, preço em reais)
-- ----------------------------------------------------------------------------
INSERT INTO services (name, description, duration_minutes, price, active)
SELECT 'Corte de cabelo', 'Corte masculino com máquina e tesoura, finalização com navalha no acabamento.', 30, 35.00, true
WHERE NOT EXISTS (SELECT 1 FROM services WHERE name = 'Corte de cabelo');

INSERT INTO services (name, description, duration_minutes, price, active)
SELECT 'Barba completa', 'Barba feita com toalha quente, navalha e óleo pós-barba.', 30, 25.00, true
WHERE NOT EXISTS (SELECT 1 FROM services WHERE name = 'Barba completa');

INSERT INTO services (name, description, duration_minutes, price, active)
SELECT 'Combo cabelo + barba', 'Corte de cabelo junto com barba completa, com desconto no valor final.', 60, 55.00, true
WHERE NOT EXISTS (SELECT 1 FROM services WHERE name = 'Combo cabelo + barba');

-- ----------------------------------------------------------------------------
-- Expediente semanal (0 = domingo … 6 = sábado)
-- Domingo (0) e segunda (1): fechados.
-- Terça (2) a sábado (6): 09:00–19:00, intervalo 12:00–13:00, slots de 30 min.
-- ----------------------------------------------------------------------------
INSERT INTO working_hours (day_of_week, closed, open_time, close_time, break_start, break_end, slot_interval_minutes)
VALUES
    (0, true,  NULL,      NULL,      NULL,      NULL,      30),
    (1, true,  NULL,      NULL,      NULL,      NULL,      30),
    (2, false, '09:00:00','19:00:00','12:00:00','13:00:00',30),
    (3, false, '09:00:00','19:00:00','12:00:00','13:00:00',30),
    (4, false, '09:00:00','19:00:00','12:00:00','13:00:00',30),
    (5, false, '09:00:00','19:00:00','12:00:00','13:00:00',30),
    (6, false, '09:00:00','19:00:00','12:00:00','13:00:00',30)
ON CONFLICT (day_of_week) DO NOTHING;
