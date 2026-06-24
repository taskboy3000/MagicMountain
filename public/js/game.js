let G = {};
let CSRF_TOKEN = '';

async function api(path, { body, method } = {}) {
  if (!method) method = body ? 'POST' : 'GET';
  const headers = { Accept: 'application/json' };
  if (body) headers['Content-Type'] = 'application/json';
  if (method !== 'GET' && CSRF_TOKEN) headers['X-CSRF-Token'] = CSRF_TOKEN;
  const resp = await fetch(path, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const data = await resp.json();
  if (data.csrf_token) CSRF_TOKEN = data.csrf_token;
  return data;
}

// ── Boot ────────────────────────────────────────────────────────
async function loadGame() {
  G = await api('/game');
  populateStatusStrip(G);
  await applyNav();
}

function populateStatusStrip(g) {
  const p = g.player || {};
  const s = g.season || {};
  document.getElementById('device-owner').textContent = p.name || '—';
  document.getElementById('s-day').textContent = s.day ?? '—';
  document.getElementById('s-total').textContent = s.total_days ?? '—';
  document.getElementById('s-ap').textContent = p.action_points ?? '—';
  document.getElementById('s-scrap').textContent = p.scrap ?? '—';
  document.getElementById('s-score').textContent = p.score ?? '—';
  document.getElementById('context-bar').textContent = '';
}

let CURRENT_VIEW = 'idle';

// ── Nav ──────────────────────────────────────────────────────────
async function applyNav(requestedView) {
  const headers = { Accept: 'application/json' };
  if (requestedView) headers['X-Nav-View'] = requestedView;
  const resp = await fetch('/nav', { headers });
  const nav = await resp.json();
  CURRENT_VIEW = nav.current_view;
  renderNavBar(nav.tabs);
  document.getElementById('context-bar').textContent = nav.context || '';
  await Promise.all([
    fetchThenRender(nav.primary_fragment_url, 'panel-primary'),
    fetchThenRender(nav.secondary_fragment_url, 'panel-secondary'),
  ]);
}

function renderNavBar(tabs) {
  const bar = document.getElementById('nav-bar');
  bar.innerHTML = tabs.map(t =>
    `<button class="nav-btn${t.active ? ' active' : ' inactive'}" data-view="${t.id}"${t.reason ? ` title="${t.reason}"` : ''}>${t.label}</button>`
  ).join('');
}

async function fetchThenRender(url, targetId) {
  if (!url) { document.getElementById(targetId).innerHTML = ''; return; }
  const resp = await fetch(url);
  if (resp.status === 204) { document.getElementById(targetId).innerHTML = ''; return; }
  const html = await resp.text();
  document.getElementById(targetId).innerHTML = html;
}

// ── Action handlers ──────────────────────────────────────────────
async function beginProspecting() {
  const data = await api('/prospecting/begin', { method: 'POST' });
  if (!data.ok) return;
  await applyNav();
}

async function pushArtifact() {
  const data = await api('/prospecting/push', { method: 'POST' });
  if (!data.ok) return;
  if (data.result === 'collapse' || data.result === 'breakthrough') {
    G = await api('/game');
    populateStatusStrip(G);
  }
  await applyNav();
}

async function stopProspecting() {
  const data = await api('/prospecting/stop', { method: 'POST' });
  if (data.ok) {
    G = await api('/game');
    populateStatusStrip(G);
    await applyNav();
  }
}

async function beginMarket() {
  const data = await api('/market/begin', { method: 'POST' });
  if (!data.ok) return;
  await applyNav();
}

async function offerItem(shedItemId) {
  const data = await api('/market/offer', { body: { shed_item_id: shedItemId }, method: 'POST' });
  if (!data.ok) return;
  if (data.result === 'sold' || data.result === 'customer_left' || data.result === 'sent_away') {
    G = await api('/game');
    populateStatusStrip(G);
  }
  await applyNav();
}

async function sendAway() {
  const data = await api('/market/send_away', { method: 'POST' });
  if (!data.ok) return;
  G = await api('/game');
  populateStatusStrip(G);
  await applyNav();
}

async function acceptCounter() {
  const data = await api('/market/accept_counter', { method: 'POST' });
  if (!data.ok) return;
  if (data.result === 'sold') {
    G = await api('/game');
    populateStatusStrip(G);
  }
  await applyNav();
}

async function purchaseSkill(skillId) {
  const data = await api('/skills/purchase', { body: { skill_id: skillId }, method: 'POST' });
  if (!data.ok) return;
  G = await api('/game');
  populateStatusStrip(G);
  await applyNav();
}

// ── Event delegation ─────────────────────────────────────────────
document.getElementById('nav-bar').addEventListener('click', (e) => {
  const btn = e.target.closest('.nav-btn');
  if (!btn || btn.classList.contains('inactive')) return;
  const view = btn.dataset.view;
  if (view === 'prospect' && CURRENT_VIEW === 'idle') { beginProspecting(); return; }
  if (view === 'bazaar' && CURRENT_VIEW === 'idle') { beginMarket(); return; }
  applyNav(view);
});

document.getElementById('panel-secondary').addEventListener('click', (e) => {
  const btn = e.target.closest('.offer-btn');
  if (btn) offerItem(btn.dataset.id);
});

document.getElementById('panel-primary').addEventListener('click', (e) => {
  const id = e.target.id;
  if (id === 'btn-push') pushArtifact();
  else if (id === 'btn-stop') stopProspecting();
  else if (id === 'btn-send-away') sendAway();
  else if (id === 'btn-accept-counter') acceptCounter();
  if (id === 'delete-account-btn') {
    if (!confirm('Delete your account permanently? This cannot be undone.')) return;
    api('/player', { method: 'DELETE' }).then(d => { if (d.ok) window.location.href = '/login'; });
    return;
  }
  const btn = e.target.closest('.buy-skill-btn');
  if (btn) purchaseSkill(btn.dataset.skill);
});

loadGame();
