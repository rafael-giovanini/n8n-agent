# 03 — Ponte Baileys (transporte WhatsApp ↔ n8n)

> **Sumário**
>
> 1. [Papel da ponte e aviso de risco](#1-papel-da-ponte-e-aviso-de-risco)
> 2. [Pré-requisitos desta etapa](#2-pré-requisitos-desta-etapa)
> 3. [Instalação passo a passo](#3-instalação-passo-a-passo)
> 4. [Arquivo `.env` da ponte (variáveis)](#4-arquivo-env-da-ponte-variáveis)
> 5. [Pareamento: QR Code ou pair code](#5-pareamento-qr-code-ou-pair-code)
> 6. [Onde a sessão é persistida](#6-onde-a-sessão-é-persistida)
> 7. [Endpoints HTTP da ponte](#7-endpoints-http-da-ponte)
> 8. [Como a ponte trata mensagens e falhas](#8-como-a-ponte-trata-mensagens-e-falhas)
> 9. [Solução de problemas comuns](#9-solução-de-problemas-comuns)
> 10. [A ponte é substituível (não é o sistema)](#10-a-ponte-é-substituível-não-é-o-sistema)

---

## 1. Papel da ponte e aviso de risco

A pasta `bridge/` contém `server.js` (Node.js, `"type": "module"`) que faz três coisas simples:

1. Conecta no WhatsApp Web pela biblioteca **Baileys**;
2. Traduz mensagens recebidas para o payload neutro da §2.1 e publica no webhook do n8n;
3. Recebe a resposta da §2.2 e reenvia cada item de `messages[]` ao cliente.

> **Aviso:** Baileys é biblioteca **não oficial** e viola os Termos de Serviço do WhatsApp/Meta; existe risco real de bloqueio do número. Leia a seção completa em [09-riscos-e-migracao-meta-cloud-api.md](09-riscos-e-migracao-meta-cloud-api.md). Em homologação, use sempre um **número comercial secundário**.

A ponte não sabe preços, não sabe horários, não agenda nada: todo negócio fica no n8n + PostgreSQL.

---

## 2. Pré-requisitos desta etapa

- Node.js **18 ou superior** instalado (`node --version` e `npm --version` devem funcionar).
- Os serviços `db` e `n8n` do Docker já estarem no ar (documento [02](02-instalacao-docker-desktop.md)).
- Pelo menos o workflow principal importado e ativado? Não é obrigatório para conectar, mas é necessário para as respostas — ordem sugerida em [04](04-importacao-workflow-n8n.md).
- Um número de WhatsApp secundário com celular por perto para escanear o QR ou receber o pair code.

---

## 3. Instalação passo a passo

Na raiz do projeto:

### 3.1 Entrar na pasta e instalar dependências

```bash
cd bridge
npm install
```

Dependências declaradas em `package.json`: `@whiskeysockets/baileys` (^6.7.x estável), `express` (^4), `qrcode-terminal` (^0.12), `pino` (^9) e `dotenv` (carrega o `bridge/.env`). O script `start` executa `node server.js`.

### 3.2 Copiar e configurar o `.env`

```bash
cp .env.example .env
```

No Windows PowerShell:

```powershell
Copy-Item .env.example .env
```

Abra `bridge/.env` e ajuste os valores conforme a próxima seção.

### 3.3 Iniciar a ponte

```bash
npm start
```

Na primeira execução, o terminal mostra o QR Code (ou o pair code, conforme a configuração). Depois do pareamento, a linha de log indica conexão aberta. Mantenha este terminal aberto: ele é a ponte.

---

## 4. Arquivo `.env` da ponte (variáveis)

| Variável | Padrão do `.env.example` | Para quê |
|---|---|---|
| `N8N_WEBHOOK_URL` | `http://localhost:5678/webhook/whatsapp/incoming` | Endereço do webhook do workflow principal (§2.1). Se o n8n usar outra porta, ajuste aqui. |
| `PORT` | `3000` | Porta do servidor Express da ponte, que expõe `POST /send` e `GET /health`. |
| `SESSION_DIR` | `./session` | Pasta onde as credenciais da sessão do WhatsApp são gravadas (`bridge/session/`). |
| `OWNER_NUMBER` | `5511999990000` | Número que receberá o pair code no formato internacional, sem `+`; usado quando `REQUEST_PAIRING_CODE=true`. |
| `REQUEST_PAIRING_CODE` | `true` | `true` pede o código de 8 dígitos por mensagem no WhatsApp (útil quando o terminal não renderiza QR); `false` usa QR Code. |
| `MESSAGE_TIMEOUT_MS` | `25000` | Tempo máximo de espera pela resposta do n8n (§2.2). Se estourar, a ponte envia `FALLBACK_MESSAGE`. |
| `FALLBACK_MESSAGE` | Texto pt-BR de instabilidade | Mensagem amigável enviada quando o n8n não responde a tempo ou a conexão falha. Nunca derruba o processo. |

Exemplo preenchido (valores de exemplo, nunca commite números reais):

```dotenv
N8N_WEBHOOK_URL=http://localhost:5678/webhook/whatsapp/incoming
PORT=3000
SESSION_DIR=./session
OWNER_NUMBER=5511999990000
REQUEST_PAIRING_CODE=true
MESSAGE_TIMEOUT_MS=25000
FALLBACK_MESSAGE=Desculpe! Estou com uma instabilidade no momento. Pode tentar novamente em instantes?
```

---

## 5. Pareamento: QR Code ou pair code

### 5.1 QR Code (modo padrão quando `REQUEST_PAIRING_CODE=false`)

1. No celular do número secundário, abra o **WhatsApp** → **Ajustes/Configurações** → **Dispositivos conectados** → **Conectar um dispositivo**.
2. Escaneie o QR exibido no terminal.
3. O log muda para conexão autenticada; a sessão passa a ser reutilizada nas próximas execuções.

### 5.2 Pair code (`REQUEST_PAIRING_CODE=true`)

Preferido em terminais que não renderizam QR (console antigo do Windows, SSH, serviços):

1. Mantenha `REQUEST_PAIRING_CODE=true` e `OWNER_NUMBER` correto.
2. Ao iniciar, a ponte chama `requestPairingCode(OWNER_NUMBER)` e imprime um código de 8 caracteres.
3. No celular: **Dispositivos conectados** → **Conectar um dispositivo** → **Conectar com número de telefone** (opção abaixo do QR) → digite o código.
4. O número precisa receber a mensagem do WhatsApp com o código; mantenha o celular por perto.

> Após o primeiro pareamento bem-sucedido, as próximas execuções reutilizam as credenciais em `bridge/session/` e não pedem novo código, a menos que a pasta seja apagada ou o número desconecte o dispositivo pela lista de aparelhos.

---

## 6. Onde a sessão é persistida

- Pasta: **`bridge/session/`** (variável `SESSION_DIR`).
- A ponte usa `useMultiFileAuthState('./session')` e salva o estado no retorno `creds.update` a cada mudança.
- Existe um arquivo vazio `bridge/session/.gitkeep` para a pasta existir no repositório; os arquivos de credencial gerados depois **não devem ser commitados** (equivalem ao login do WhatsApp).
- Para "deslogar de vez": pare o processo, apague o conteúdo de `bridge/session/` e inicie novamente (`npm start`).

---

## 7. Endpoints HTTP da ponte

### 7.1 `GET /health`

Usado para checar se a conexão com o WhatsApp está aberta:

```bash
curl http://localhost:3000/health
```

Resposta esperada:

```json
{ "status": "ok", "connected": true }
```

| `connected` | Significado | Ação |
|---|---|---|
| `true` | Sessão autenticada e conectada | Operação normal. |
| `false` | Reconectando, pareamento pendente ou desconectado | Ver logs do terminal; complete o pareamento se necessário. |

### 7.2 `POST /send` (envio assíncrono, §2.3)

Permite que rotinas do n8n (ex.: lembretes futuros) enviem uma mensagem isolada sem ser pela resposta do webhook:

```bash
curl -X POST http://localhost:3000/send ^
  -H "Content-Type: application/json" ^
  -d "{\"to\":\"5511999990000\",\"text\":\"Seu agendamento foi confirmado...\"}"
```

No Git Bash/Linux:

```bash
curl -X POST http://localhost:3000/send \
  -H "Content-Type: application/json" \
  -d '{"to":"5511999990000","text":"Seu agendamento foi confirmado..."}'
```

Respostas possíveis:

- Sucesso: `{ "ok": true, "sent": true }`
- Erro: HTTP 500 `{ "ok": false, "error": "..." }`

### 7.3 Recepção (webhook de saída da ponte)

A ponte mesma faz `POST` em `N8N_WEBHOOK_URL` com o JSON da §2.1. O endereço de entrada do n8n e o formato do payload estão documentados em [01-arquitetura.md](01-arquitetura.md#3-contrato-de-payload-neutro-2-do-contrato).

---

## 8. Como a ponte trata mensagens e falhas

- **Filtros:** ignora mensagens de grupos (`@g.us`), mensagens próprias (`fromMe`) e status de "status" (stories).
- **Extração de texto:** `message.conversation || message.extendedTextMessage?.text`; mídia (imagem, áudio, vídeo) gera uma mensagem genérica avisando que no momento a atendente só entende texto.
- **Envio da resposta:** para cada item de `messages[]` do §2.2, a ponte executa `sock.sendMessage(jid, { text })`.
- **Timeout:** se o n8n não responder dentro de `MESSAGE_TIMEOUT_MS`, a ponte envia o `FALLBACK_MESSAGE`; o processo não é encerrado.
- **Reconexão:** no evento `connection.update.close`, a ponte agenda reconexão com atraso exponencial (backoff), preservando a sessão em `bridge/session/`.

---

## 9. Solução de problemas comuns

| Problema | Possível causa | Como resolver |
|---|---|---|
| **QR Code não aparece no terminal** | Console do Windows sem renderização Unicode/ANSI; versões antigas do terminal | Troque para `REQUEST_PAIRING_CODE=true` e use o pair code (§5.2); ou use Windows Terminal/PowerShell moderno. |
| **QR aparece mas ao escanear dá erro** | Sessão antiga corrompida em `bridge/session/`; QR expirou | Pare com `Ctrl + C`, apague o conteúdo de `bridge/session/` (mantenha o `.gitkeep`), `npm start` novamente e escaneie/QR novo. |
| **Número banido/bloqueado** | Uso não oficial detectado pela Meta; frequência alta ou mensagens não solicitadas | Ver [09](09-riscos-e-migracao-meta-cloud-api.md): use número secundário, reduza frequência, migre para a Cloud API. Não insista no mesmo número para recuperação imediata. |
| **Mensagem de instabilidade (`FALLBACK_MESSAGE`) ao responder clientes** | O n8n não respondeu dentro de `MESSAGE_TIMEOUT_MS`; workflow desativado; credencial Gemini ausente; erro no agente | 1. Confirmar workflow principal **ativado** no n8n; 2. conferir credenciais `Google Gemini API` e `Postgres Barbearia` ([05](05-credenciais-e-segredos.md)); 3. ver aba **Execuções** (Executions) no n8n para o erro; 4. se o modelo demora, aumente `MESSAGE_TIMEOUT_MS` para 30000–45000. |
| **Webhook timeout (erro de fetch no log da ponte)** | `N8N_WEBHOOK_URL` errado; n8n fora do ar; porta diferente de 5678 | Conferir `docker compose ps` (n8n healthy), conferir a URL no `.env` da ponte e o caminho do webhook (`whatsapp/incoming`); reiniciar com `docker compose restart n8n`. |
| **A resposta chega duplicada** | A ponte reconectou e reprocessou a mesma mensagem, ou o workflow tem duas ativações | Reinicie a ponte uma única vez; desative workflows duplicados no n8n; verifique se não há duas instâncias da ponte rodando (`npm start` em dois terminais). |
| **Mídia recebida e a Bia "não entende"** | Comportamento esperado desta versão | A ponte avisa que só entende texto; não implemente processamento de mídia sem atualizar o contrato. |
| **Após reiniciar o computador a ponte pede pareamento de novo** | Conteúdo de `bridge/session/` apagado (limpeza/disk cleanup) ou sessão revogada no WhatsApp | Reautorize pelo celular (Dispositivos conectados); nunca commite nem sincronize a pasta em nuvem. |
| **`npm install` falha de rede** | Firewall/proxy bloqueando registry do npm | Configure proxy do npm ou repita em rede liberada; não altere as versões das dependências do `package.json`. |

---

## 10. A ponte é substituível (não é o sistema)

Lembrete arquitetural (detalhe em [01](01-arquitetura.md#4-princípio-do-adaptador-isolado) e guia em [09](09-riscos-e-migracao-meta-cloud-api.md)):

- A ponte fala **apenas** o payload neutro da §2 (entrada §2.1, resposta §2.2, envio §2.3).
- Quando a migração para a Meta WhatsApp Cloud API for feita, cria-se uma pasta **`bridge-meta/`** com o mesmo contrato; `docker-compose.yml`, workflows, PostgreSQL, credenciais e o prompt da Bia continuam intactos.
- Nenhuma regra de agendamento deve ser implementada em `server.js`: se uma regra existe, ela pertence ao SQL ou a um sub-workflow em `n8n/tools/`.

Próxima etapa: [04 — Importação dos workflows no n8n](04-importacao-workflow-n8n.md).
