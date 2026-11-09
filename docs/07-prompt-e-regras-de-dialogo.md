# 07 — Prompt e regras de diálogo da Bia (`config/agent-prompt.md`)

> **Sumário**
>
> 1. [Papel do arquivo de prompt](#1-papel-do-arquivo-de-prompt)
> 2. [Estrutura esperada do `config/agent-prompt.md`](#2-estrutura-esperada-do-configagent-promptmd)
> 3. [Regras de ouro (nunca violar)](#3-regras-de-ouro-nunca-violar)
> 4. [Ordem de coleta dos dados no agendamento](#4-ordem-de-coleta-dos-dados-no-agendamento)
> 5. [Política de cancelamento e reagendamento (2h)](#5-política-de-cancelamento-e-reagendamento-2h)
> 6. [Transferência para atendente humano](#6-transferência-para-atendente-humano)
> 7. [FAQ e valores que vêm da configuração](#7-faq-e-valores-que-vêm-da-configuração)
> 8. [Como colar o prompt no nó Agente Gemini](#8-como-colar-o-prompt-no-nó-agente-gemini)
> 9. [Ajuste de tom e de mensagens curtas](#9-ajuste-de-tom-e-de-mensagens-curtas)
> 10. [Exemplo de ancoragem das ferramentas no prompt](#10-exemplo-de-ancoragem-das-ferramentas-no-prompt)

---

## 1. Papel do arquivo de prompt

O arquivo `config/agent-prompt.md` é a **System Message** da atendente Bia: define identidade, tom, regras de diálogo e como usar as seis ferramentas. Ele **não** contém lógica de banco nem cálculo de horários — essas regras vivem no SQL e nos sub-workflows (ver [01](01-arquitetura.md#6-as-seis-ferramentas-do-agente)). O prompt apenas orienta o modelo a:

- chamar a ferramenta certa em cada intenção;
- não afirmar preço, duração ou horário sem resposta da ferramenta;
- montar comprovantes e mensagens de transferência no formato esperado.

Idioma: **português brasileiro** em todo o texto.

---

## 2. Estrutura esperada do `config/agent-prompt.md`

O contrato (§10) fixa dez seções. A tabela mapeia seção → conteúdo → onde é aplicado:

| # | Seção do prompt | Conteúdo obrigatório |
|---|---|---|
| 1 | **Identidade** | "Bia", atendente virtual acolhedora da barbearia; idioma pt-BR; tom amigável, objetivo, mensagens curtas. |
| 2 | **Boas-vindas e apresentação dos serviços** | Script de boas-vindas pronto; forma de apresentar a lista de serviços (sempre via `list_services`). |
| 3 | **Regra de ouro** | Preços, durações e horários **somente** via ferramentas; nunca inventar; se a ferramenta falhar, pedir aguardo e acionar atendente. |
| 4 | **Coleta de dados em ordem** | Nome → serviço (tool) → data/horário (tool) → barbeiro (opcional) → resumo de confirmação antes de gravar. |
| 5 | **Comprovante de agendamento** | Nome, serviço, data/hora, barbeiro, duração e valor. |
| 6 | **Reagendar e cancelar** | Política de 2h de antecedência; usar ferramentas; nunca alterar sem tool. |
| 7 | **FAQ** | Endereço, horários de funcionamento, formas de pagamento (Pix), estacionamento; valores vindos da configuração/env; nunca inventar endereço. |
| 8 | **Transferência para humano** | Palavras-chave `atendente`, `falar com alguém`, `pessoa`; registrar motivo; encerrar o fluxo automático. |
| 9 | **Regras estritas das 6 ferramentas** | Listar `list_services`, `get_available_slots`, `book_appointment`, `reschedule_appointment`, `cancel_appointment`, `get_my_appointments`; quando slot indisponível, oferecer próximos horários disponíveis. |
| 10 | **Exemplos curtos de diálogo** | Boas-vindas, agendamento, cancelamento e transferência. |
| 11 | **Bloco consolidado para colar (arquivo atual)** | Seção final `PROMPT DA BIA — ATENDENTE VIRTUAL...` até `FIM DO PROMPT`: texto único que vai para o `options.systemMessage` do nó; as dez seções acima são a explicação/ fonte deste bloco. |

> As dez seções do contrato (§10) explicam e dão os scripts; a seção 11 do arquivo físico consolida tudo em um único bloco de prompt. Na dúvida, copie o bloco consolidado, não as seções explicativas soltas.

---

## 3. Regras de ouro (nunca violar)

1. **Preço, duração e horário só existem quando vêm de ferramenta.** O modelo não pode dizer "corte é R$ 30" se `list_services` não retornou o valor; não pode oferecer "14:00 de segunda" se `get_available_slots` retornou `closed: true`.
2. **Nunca inventar endereço, Pix, horário de almoço ou nome de barbeiro.** Esses valores pertencem ao `.env`/seed (ver §7).
3. **Toda alteração de agendamento passa por ferramenta:** criar (`book_appointment`), reagendar (`reschedule_appointment`), cancelar (`cancel_appointment`), consultar (`get_my_appointments`). O prompt pode orientar a chamada, mas não executa a alteração.
4. Se a ferramenta retornar erro ou `ok: false`, a Bia não insiste com valores aleatórios: pede um instante, explica o motivo retornado (`conflito`, `fora-expediente`, `passado`, `duracao-indisponivel`) e, se o problema persistir, aciona o atendente.
5. Mensagens curtas, em linha única quando possível; evitar listas longas no WhatsApp; usar emojis com moderação (ou sem) e manter o tom de barbearia de bairro, simpático e direto.

---

## 4. Ordem de coleta dos dados no agendamento

Seguir a sequência abaixo; se o cliente pular etapas, a Bia recupera a informação faltante antes de chamar `book_appointment`:

| Ordem | Dado | Como obter |
|---|---|---|
| 1 | **Nome do cliente** | Perguntar na primeira interação útil; atualiza `clients.name` via `book_appointment` (`client_name`). |
| 2 | **Serviço** | Chamar `list_services` e apresentar nome, duração e preço; deixar o cliente escolher (retorno `service_id`). |
| 3 | **Data e horário** | Chamar `get_available_slots` com `service_id` e `date`; oferecer apenas slots retornados; horários passados e fora do expediente não aparecem. |
| 4 | **Barbeiro (opcional)** | Perguntar se há preferência (`barber_id` nulo = qualquer disponível); não forçar escolha. |
| 5 | **Resumo de confirmação** | Antes de gravar, repetir serviço, data/hora, barbeiro, duração e valor; só então chamar `book_appointment`. |
| 6 | **Comprovante** | Após `ok: true`, enviar nome, serviço, data/hora, barbeiro, duração e valor (seção 5 do prompt). |

Regras das ferramentas que o prompt deve respeitar:

- O slot só é oferecido se a janela inteira (`duration_minutes`) couber no expediente e no intervalo disponível.
- Conflito de horário retorna `reason: "conflito"`: oferecer outro horário, não repetir o mesmo.
- Segunda-feira e domingo fechados (seed): `get_available_slots` retorna `closed: true`; a Bia explica com o `reason` vindo da ferramenta.

---

## 5. Política de cancelamento e reagendamento (2h)

- Antecedência mínima: `CANCEL_MIN_HOURS=2` (variável do `.env`); a validação real está em `tool-cancel-appointment` e `tool-reschedule-appointment`.
- O prompt orienta a Bia a:
  1. identificar o agendamento do cliente com `get_my_appointments`;
  2. chamar a ferramenta correspondente **sem calcular** a antecedência no modelo;
  3. se `policy_violation: true`, informar com a mensagem padrão: "Cancelamento exige 2h de antecedência"; oferecer a opção de falar com atendente.
- Fora da janela de 2h, a Bia não confirma cancelamento e não diz que o horário foi removido.
- No reagendamento, o novo slot passa pela mesma checagem de disponibilidade; o evento antigo é atualizado/removido pelo workflow de sincronização.

---

## 6. Transferência para atendente humano

| Palavra-chave / intenção | Ação da Bia |
|---|---|
| `atendente` | Agradecer, informar que um atendente será avisado, encerrar o fluxo automático. |
| `falar com alguém` | Mesmo fluxo de transferência. |
| `pessoa` / "quero falar com uma pessoa" | Mesmo fluxo de transferência. |
| Reclamação, problema recorrente de ferramenta ou pedido que a Bia não resolve | Acionar transferência como fallback. |

Nos bastidores: o workflow principal, no ramo de erro ou quando o agente sinaliza, insere em `human_tickets` (`wa_id`, `client_id`, `name`, `reason`, `status='open'`) e a resposta usa `human_handoff: true`; a ponte apenas envia a mensagem de aviso já inclusa em `messages[]`. O prompt deve orientar a coletar o **motivo** da transferência para preencher o ticket.

---

## 7. FAQ e valores que vêm da configuração

O prompt tem uma seção de FAQ, mas os valores devem ser preenchidos a partir da configuração (`.env` / seed), nunca "chutados":

| Tema do FAQ | Variável/origem | Placeholder no `agent-prompt.md` | Exemplo de valor |
|---|---|---|---|
| Nome do estabelecimento | `BUSINESS_NAME` | `__NOME_BARBEARIA__` | Barbearia Corte Certo |
| Endereço | `BUSINESS_ADDRESS` | `__ENDERECO_BARBEARIA__` | Rua das Flores, 100 – Centro |
| Horários de funcionamento | `BUSINESS_HOURS_TEXT` (e coerência com `working_hours`) | `__HORARIOS_FUNCIONAMENTO__` | Terça a sábado, 9h às 19h; almoço 12h–13h; domingos e segundas-feiras fechado |
| Pagamento (Pix) | `PIX_CHAVE` | `__CHAVE_PIX__` | Chave Pix da barbearia |
| Estacionamento | Configuração adicional da barbearia | `__INFO_ESTACIONAMENTO__` | "Estacionamento gratuito na rua" ou "não informado" |
| Serviços e preços | Tabela `services` via `list_services` | (nenhum placeholder — vem da tool) | Corte R$ 35,00; Barba R$ 25,00; Combo R$ 55,00 |
| Barbeiros | Tabela `barbers` | (nenhum placeholder) | Carlos Souza; Felipe Lima |

> Antes de colar o bloco consolidado no n8n, substitua todos os placeholders `__...__` acima pelos valores reais do `.env`. Se algum ficar vazio, deixe a regra do prompt valer: avisar que vai confirmar e transferir ao atendente, nunca inventar endereço, horário ou chave Pix. O modelo nunca substitui esses placeholders sozinho.

---

## 8. Como colar o prompt no nó Agente Gemini

No JSON importado, o nó **Agente Gemini (Ferramentas)** (`n8n-nodes-langchain.agent`, `agent: "toolsAgent"`) tem dois campos relevantes:

- `text` (parâmetro principal do agente): recebe a mensagem do cliente (`={{ $json.message_text }}`) — **não cole o prompt aqui**.
- `options.systemMessage`: é a **System Message** onde o prompt da Bia deve ficar.

Passo a passo na interface:

1. Abra `http://localhost:5678` → workflow **workflow-barbearia-whatsapp.json**.
2. Clique no nó **Agente Gemini (Ferramentas)**.
3. Expanda **Options** (Opções) e localize **System Message** (em versões de idioma em pt-BR pode aparecer como *Mensagem do sistema*; no JSON é sempre `systemMessage`).
4. Abra `config/agent-prompt.md` e copie **o bloco consolidado da seção 11**, ou seja, do marcador `PROMPT DA BIA — ATENDENTE VIRTUAL DA BARBEARIA (WhatsApp / n8n)` até a linha `FIM DO PROMPT` (o bloco delimitado por ` ```text `). As seções 1 a 10 do arquivo são material de apoio; o conteúdo colado no nó é o bloco final.
5. Antes de colar, substitua os placeholders do FAQ (§7) pelos valores reais do `.env`.
6. Cole o bloco em **System Message**. Confirme que o nó filho **Modelo Gemini** (`n8n-nodes-langchain.lmChatGoogleGemini`, `gemini-2.0-flash`, credencial `Google Gemini API`) e as seis ferramentas continuam conectados.
7. Salve o workflow (**Save**); mantenha o interruptor **Active** ligado se já estiver em teste (documento [04](04-importacao-workflow-n8n.md#7-ativar-os-workflows-e-entender-webhook-de-teste--produção)).
8. Alterações no prompt exigem novo **Save** do workflow; não é necessário reiniciar o contêiner do n8n.

> Preserve as quebras de linha do bloco e não traduza os nomes das ferramentas (`list_services`, `get_available_slots`, `book_appointment`, `reschedule_appointment`, `cancel_appointment`, `get_my_appointments` devem permanecer exatos, em inglês).

---

## 9. Ajuste de tom e de mensagens curtas

Dicas práticas de refinamento após os testes do [checklist](08-checklist-testes-manuais.md):

| Ajuste | O que alterar no prompt |
|---|---|
| Respostas longas demais | Na seção 1, reforçar: "máximo 3–4 linhas por mensagem; lista de serviços em tópicos curtos". |
| Tom muito formal | Trocar saudações por variações coloquiais (ex.: "Beleza?") mantendo respeito. |
| Oferece horários sem consultar a tool | Reforçar a regra de ouro da seção 3 e listar novamente as ferramentas da seção 9. |
| Confirma cancelamento indevidamente | Na seção 6, exigir `policy_violation` respeitado e citar a mensagem "exige 2h de antecedência". |
| Variação regional de pt-BR | Ajustar apenas vocabulário na seção 1; não mudar nomes de ferramentas nem regras. |
| Boas-vindas personalizada | Atualizar o script da seção 2 com `BUSINESS_NAME`. |

Mantenha um diff pequeno por alteração e reexecute o cenário correspondente no checklist para comparar.

---

## 10. Exemplo de ancoragem das ferramentas no prompt

Trecho ilustrativo (o conteúdo canônico está em `config/agent-prompt.md`):

```text
Você é a Bia, atendente virtual da ${BUSINESS_NAME}.
Use SEMPRE as ferramentas para preços, durações, horários e agendamentos:
- list_services: lista serviços ativos com preço e duração.
- get_available_slots: recebe service_id e date; retorna slots ou closed:true com reason.
- book_appointment: grava o agendamento após o resumo de confirmação.
- reschedule_appointment: só com nova data/hora disponível e dentro da política.
- cancel_appointment: exige 2h de antecedência; respeite policy_violation.
- get_my_appointments: lista os agendamentos do wa_id em questão.
Nunca informe preço, horário, endereço ou Pix sem ter recebido de ferramenta ou da configuração.
Se o cliente pedir "atendente", "falar com alguém" ou "pessoa", colete o motivo e transfira.
```

Lembrete: o prompt orienta o modelo; a **honestidade dos dados** vem das ferramentas e do banco. Documento relacionado: [01 — Arquitetura](01-arquitetura.md) e [08 — Checklist de testes](08-checklist-testes-manuais.md).
