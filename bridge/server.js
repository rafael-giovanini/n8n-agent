/**
 * ============================================================================
 * PONTE WHATSAPP (Baileys) -> n8n — Atendimento da Barbearia
 * ============================================================================
 * Papel deste arquivo (adaptador ISOLADO, conforme contrato §9 e §2):
 *  - Esta pasta `bridge/` é o único ponto de contato com o WhatsApp.
 *  - Ela converte mensagens do Baileys no PAYLOAD NEUTRO da §2.1 e POSTa em
 *    N8N_WEBHOOK_URL; nunca expõe detalhes do Baileys para o n8n.
 *  - A resposta do n8n segue a §2.2 (`messages[]` + `human_handoff`) e aqui
 *    apenas cada `messages[].text` é enviado de volta no WhatsApp.
 *  - Migração futura para a Meta Cloud API: trocar somente esta pasta; o
 *    payload enviado ao n8n e a resposta lida continuam os mesmos do §2.1/§2.2.
 *    Ver roadmap em docs/09-riscos-e-migracao-meta-cloud-api.md (documento
 *    entregue pelo bloco de Docs; aqui apenas a referência).
 *
 * Observação: o Baileys (@whiskeysockets/baileys) é uma biblioteca NÃO OFICIAL
 * do WhatsApp; mantê-la isolada aqui evita que decisões de protocolo de
 * mensagem vazem para as regras de negócio no n8n.
 * ============================================================================
 */

// Carrega variáveis de ambiente do arquivo .env local (não substituído em produção)
import 'dotenv/config';
import express from 'express';
import qrcode from 'qrcode-terminal';
import pino from 'pino';
import {
  makeWASocket,
  useMultiFileAuthState,
  Browsers,
  DisconnectReason,
} from '@whiskeysockets/baileys';

// ---------------------------------------------------------------------------
// Bloco de configuração: tudo vem de process.env (ver bridge/.env.example)
// ---------------------------------------------------------------------------
const N8N_WEBHOOK_URL =
  process.env.N8N_WEBHOOK_URL || 'http://localhost:5678/webhook/whatsapp/incoming';
const PORT = Number(process.env.PORT || 3000);
const SESSION_DIR = process.env.SESSION_DIR || './session';
// Apenas dígitos, no formato DDI + DDD + número, sem sinais nem @s.whatsapp.net
const OWNER_NUMBER = (process.env.OWNER_NUMBER || '').replace(/\D/g, '');
// true  = usa código de pareamento (requestPairingCode) em vez do QR no terminal
// false = exibe o QR no terminal para escanear com o aparelho
const REQUEST_PAIRING_CODE = process.env.REQUEST_PAIRING_CODE === 'true';
// Timeout (ms) do POST ao n8n antes de enviar a mensagem de fallback amigável
const MESSAGE_TIMEOUT_MS = Number(process.env.MESSAGE_TIMEOUT_MS || 25000);
// Mensagem enviada ao cliente quando o n8n não responde dentro do timeout
const FALLBACK_MESSAGE =
  process.env.FALLBACK_MESSAGE ||
  'Desculpe! Estou com dificuldade para processar sua mensagem agora. Pode tentar novamente em alguns instantes?';

// ---------------------------------------------------------------------------
// Estado global da conexão (lido pelo GET /health)
// ---------------------------------------------------------------------------
let sock = null;
let connected = false;
let reconectando = false;
// Atraso inicial de reconexão; dobra a cada falha até o teto de 60s
let atrasoReconexaoMs = 2000;
const ATRASO_MAXIMO_MS = 60000;

// ---------------------------------------------------------------------------
// Criação do socket Baileys com estado salvo em múltiplos arquivos (§9)
// ---------------------------------------------------------------------------
async function iniciarSocket() {
  if (reconectando) return;
  reconectando = true;

  try {
    // useMultiFileAuthState: persiste as credenciais na pasta SESSION_DIR
    const { state, saveCreds } = await useMultiFileAuthState(SESSION_DIR);
    const podeParear = REQUEST_PAIRING_CODE && !state.creds.registered && OWNER_NUMBER;

    sock = makeWASocket({
      auth: state,
      // Log interno do Baileys silencioso; nossos avisos usam console.log/warn
      logger: pino({ level: 'silent' }),
      browser: Browsers.macOS('Chrome'),
      // Com pareamento por código, não imprimimos QR no terminal
      ...(podeParear ? { printQRInTerminal: false } : {}),
    });

    // Sempre que as credenciais forem atualizadas, salva em disco (creds.update)
    sock.ev.on('creds.update', saveCreds);

    // Pareamento por número quando não existe sessão ainda (§9)
    if (podeParear) {
      setTimeout(async () => {
        try {
          const codigo = await sock.requestPairingCode(OWNER_NUMBER);
          console.log(`\nCódigo de pareamento (digite no WhatsApp do aparelho): ${codigo}\n`);
        } catch (err) {
          console.warn('Não foi possível solicitar o código de pareamento:', err?.message);
        }
      }, 3000);
    }

    // Registro dos handlers de evento
    sock.ev.on('connection.update', lidarAtualizacaoConexao);
    sock.ev.on('messages.upsert', lidarMensagensRecebidas);
  } finally {
    reconectando = false;
  }
}

// ---------------------------------------------------------------------------
// Handler de connection.update: QR, abertura, fechamento e reconexão (§9)
// ---------------------------------------------------------------------------
async function lidarAtualizacaoConexao(update) {
  const { connection, lastDisconnect, qr } = update;

  // Exibe o QR no terminal quando o pareamento por código não está habilitado
  if (qr && !REQUEST_PAIRING_CODE) {
    console.log('\nQR Code abaixo — escaneie no WhatsApp: Aparelhos conectados > Adicionar:\n');
    qrcode.generate(qr, { small: true });
  }

  if (connection === 'open') {
    connected = true;
    atrasoReconexaoMs = 2000;
    console.log('WhatsApp conectado e pronto para receber mensagens.');
  }

  if (connection === 'close') {
    connected = false;
    const statusCode = lastDisconnect?.error?.output?.statusCode;

    if (statusCode === DisconnectReason.loggedOut) {
      // Sessão revogada no aparelho: usuário deve apagar a pasta session/ e escanear
      // o QR (ou gerar novo código) novamente. Não encerramos o processo.
      console.warn(
        'Sessão desconectada (loggedOut): apague a pasta session/ e escaneie o QR ' +
          '(ou gere o código de pareamento) novamente ao reconectar.'
      );
      atrasoReconexaoMs = 2000;
    } else {
      // Atraso exponencial: 2s -> 4s -> 8s -> ... -> teto de 60s
      atrasoReconexaoMs = Math.min(atrasoReconexaoMs * 2, ATRASO_MAXIMO_MS);
      console.warn(
        `Conexão fechada (motivo: ${lastDisconnect?.error?.message || statusCode}). ` +
          `Reconectando em ${atrasoReconexaoMs}ms...`
      );
    }

    // Agenda a reconexão sem derrubar o processo
    setTimeout(iniciarSocket, atrasoReconexaoMs);
  }
}

// ---------------------------------------------------------------------------
// Handler de messages.upsert (§9): filtros e extração de texto
// ---------------------------------------------------------------------------
async function lidarMensagensRecebidas({ messages, type }) {
  // Apenas notificações novas do remetente; ignora ecos de envio próprio
  if (type !== 'notify') return;

  for (const mensagem of messages) {
    try {
      await processarMensagem(mensagem);
    } catch (err) {
      // Erro em uma mensagem individual nunca pode encerrar o processo (§9)
      console.warn('Erro ao processar uma mensagem individual:', err?.message);
    }
  }
}

async function processarMensagem(msg) {
  const jid = msg.key?.remoteJid;
  if (!jid) return;

  // Filtros do §9: ignorar grupos, broadcast de status e mensagens enviadas por nós
  if (jid.endsWith('@g.us')) return; // grupos
  if (jid === 'status@broadcast') return; // status/histórias
  if (msg.key?.fromMe) return; // mensagens próprias

  const conteudo = msg.message || {};
  // Extrai texto: mensagem simples ou texto de mensagem longa (extendedTextMessage)
  const texto =
    conteudo.conversation || conteudo.extendedTextMessage?.text || '';

  // Mídia não textual: imagem, vídeo, áudio, documento, figurinha, localização, contato
  const temMidiaNaoTexto = Boolean(
    !texto &&
      (conteudo.imageMessage ||
        conteudo.videoMessage ||
        conteudo.audioMessage ||
        conteudo.documentMessage ||
        conteudo.stickerMessage ||
        conteudo.locationMessage ||
        conteudo.contactMessage)
  );

  // wa_id: número no formato internacional, sem @s.whatsapp.net (§2.1)
  const waId = jid.split('@')[0].replace(/\D/g, '');
  const senderName = msg.pushName || '';
  const messageId = msg.key?.id || '';
  // messageTimestamp vem em segundos (epoch); normaliza para milissegundos
  let timestamp = Number(msg.messageTimestamp) || Date.now();
  if (timestamp < 1e12) timestamp = timestamp * 1000;

  if (temMidiaNaoTexto) {
    // A ponte só entende texto no momento: avisa o cliente de forma amigável (§9)
    await sock.sendMessage(jid, {
      text: 'No momento eu só consigo ler mensagens de texto. Pode mandar o que você precisa por escrito?',
    });
  }

  // Monta o payload neutro da §2.1 (provider sempre "baileys" nesta versão)
  const payload = {
    provider: 'baileys',
    wa_id: waId,
    sender_name: senderName,
    message_id: messageId,
    message_type: texto ? 'text' : 'media',
    message_text: texto, // vazio para mídia não textual (§2.1)
    timestamp,
  };

  await entregarNoN8N(payload, jid);
}

// ---------------------------------------------------------------------------
// POST ao webhook do n8n (§2.1) com timeout; leitura da resposta §2.2 (§9)
// ---------------------------------------------------------------------------
async function entregarNoN8N(payload, jid) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), MESSAGE_TIMEOUT_MS);

  try {
    const resposta = await fetch(N8N_WEBHOOK_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });

    if (!resposta.ok) {
      throw new Error(`Webhook do n8n retornou HTTP ${resposta.status}`);
    }

    const dados = await resposta.json();

    // §2.2: cada item de messages[].text vira uma mensagem WhatsApp enviada pela ponte
    if (Array.isArray(dados.messages)) {
      for (const item of dados.messages) {
        if (item && typeof item.text === 'string' && item.text.trim()) {
          await sock.sendMessage(jid, { text: item.text });
        }
      }
    }

    // human_handoff=true: a pendência foi registrada no n8n (human_tickets) e a
    // mensagem de transferência já veio dentro de messages[]; a ponte apenas a
    // envia e não gera nenhum texto extra (§2.2).
    if (dados.human_handoff === true) {
      console.log(`Transferência para atendente humano registrada para ${payload.wa_id}.`);
    }
  } catch (err) {
    // Falha de rede/timeout/parse: fallback amigável ao cliente; nunca derruba o processo
    console.warn('Falha ao entregar mensagem ao n8n:', err?.message);
    await sock.sendMessage(jid, { text: FALLBACK_MESSAGE });
  } finally {
    clearTimeout(timer);
  }
}

// ---------------------------------------------------------------------------
// API local Express: POST /send (§2.3) e GET /health (§2)
// ---------------------------------------------------------------------------
const app = express();
app.use(express.json());

// Health check simples: usado pelo Docker/compose e pelos workflows de rotina
app.get('/health', (req, res) => {
  res.json({ status: 'ok', connected: connected });
});

// Envio assíncrono: n8n (ou rotina) chama com { "to": "55...", "text": "..." }
app.post('/send', async (req, res) => {
  try {
    const { to, text } = req.body || {};

    if (!to || typeof text !== 'string' || !text.trim()) {
      return res.status(400).json({
        ok: false,
        error: 'Corpo inválido: informe "to" (número) e "text" (mensagem não vazia).',
      });
    }

    // Normaliza para JID do WhatsApp mesmo se vier só o número
    const jid = to.includes('@') ? to : `${String(to).replace(/\D/g, '')}@s.whatsapp.net`;

    if (!sock) {
      throw new Error('Socket do WhatsApp ainda não está inicializado.');
    }

    await sock.sendMessage(jid, { text });
    res.json({ ok: true, sent: true });
  } catch (err) {
    res.status(500).json({ ok: false, error: err?.message || 'Erro interno ao enviar.' });
  }
});

app.listen(PORT, () => {
  console.log(`API da ponte ouvindo em http://localhost:${PORT} (POST /send, GET /health).`);
});

// ---------------------------------------------------------------------------
// Partida do serviço: qualquer falha inicial também reconecta com backoff
// ---------------------------------------------------------------------------
iniciarSocket().catch((err) => {
  console.warn('Falha ao iniciar o socket:', err?.message);
  setTimeout(iniciarSocket, atrasoReconexaoMs);
});
