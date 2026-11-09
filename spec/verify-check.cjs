const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..');
const files = [];
function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p);
    else if (e.name.endsWith('.json')) files.push(p);
  }
}
walk(path.join(root, 'n8n'));
files.push(path.join(root, 'bridge', 'package.json'));
let bad = 0;
for (const f of files) {
  try {
    const j = JSON.parse(fs.readFileSync(f, 'utf8'));
    const rel = path.relative(root, f);
    if (rel.startsWith('n8n')) {
      const nodes = j.nodes || [];
      const conns = Object.keys(j.connections || {});
      const types = nodes.map(n => n.type);
      const toolWf = types.filter(t => t === 'n8n-nodes-langchain.toolWorkflow').length;
      const gemini = types.filter(t => t === 'n8n-nodes-langchain.lmChatGoogleGemini').length;
      const webhook = types.filter(t => t === 'n8n-nodes-base.webhook').length;
      const resp = types.filter(t => t === 'n8n-nodes-base.respondToWebhook').length;
      const pg = types.filter(t => t === 'n8n-nodes-base.postgres').length;
      console.log(`OK ${rel} | nodes=${nodes.length} toolWorkflow=${toolWf} gemini=${gemini} webhook=${webhook} respond=${resp} postgres=${pg} conns=[${conns.join(',')}] active=${j.active}`);
    } else {
      const deps = Object.keys(j.dependencies || {}).join(',');
      console.log(`OK ${rel} | deps=${deps}`);
    }
  } catch (e) {
    bad++;
    console.log(`FAIL ${f} :: ${e.message}`);
  }
}
// checagens de conteúdo no workflow principal
const main = JSON.parse(fs.readFileSync(path.join(root, 'n8n', 'workflow-barbearia-whatsapp.json'), 'utf8'));
const names = main.nodes.map(n => n.name);
const checks = {
  webhookPath: main.nodes.find(n => n.type === 'n8n-nodes-base.webhook')?.parameters?.path === 'whatsapp/incoming',
  sixTools: main.nodes.filter(n => n.type === 'n8n-nodes-langchain.toolWorkflow').length === 6,
  agentNode: main.nodes.some(n => n.type === 'n8n-nodes-langchain.agent'),
  stateUpsert: main.nodes.some(n => n.type === 'n8n-nodes-base.postgres' && JSON.stringify(n.parameters || {}).includes('conversation_state')),
  ticketInsert: main.nodes.some(n => n.type === 'n8n-nodes-base.postgres' && JSON.stringify(n.parameters || {}).includes('human_tickets')),
  geminiModel: JSON.stringify(main.nodes).includes('gemini-2.0-flash'),
};
console.log('--- checagens de conteúdo (workflow principal) ---');
for (const [k, v] of Object.entries(checks)) console.log(`${v ? 'PASS' : 'FAIL'} ${k}`);
console.log(bad ? `${bad} JSON COM FALHA` : 'ALL_JSON_OK');
