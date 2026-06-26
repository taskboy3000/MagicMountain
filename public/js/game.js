let CSRF_TOKEN = '';

async function api(path, { body, method } = {}) {
  if (!method) method = body ? 'POST' : 'GET';
  const headers = { Accept: 'application/json' };
  if (body) headers['Content-Type'] = 'application/json';
  if (method !== 'GET' && CSRF_TOKEN) headers['X-CSRF-Token'] = CSRF_TOKEN;
  const resp = await fetch(path, { method, headers, body: body ? JSON.stringify(body) : undefined, redirect: 'manual' });
  let data;
  try {
    data = await resp.json();
  } catch (_) {
    window.location.href = '/game';
    return;
  }
  if (data.csrf_token) CSRF_TOKEN = data.csrf_token;
  return data;
}

// ── Generic action handler ──────────────────────────────────────
async function handleAction(btn) {
  const actionUrl = btn.dataset.actionUrl;
  if (!actionUrl) return;
  if (btn.dataset.confirm && !confirm(btn.dataset.confirm)) return;
  const method = btn.dataset.method || 'POST';
  const body = {};
  for (const key of Object.keys(btn.dataset)) {
    if (key === 'actionUrl' || key === 'method' || key === 'confirm' || key === 'redirect') continue;
    body[key.replace(/([A-Z])/g, '_$1').toLowerCase()] = btn.dataset[key];
  }
  const data = await api(actionUrl, { method, body: Object.keys(body).length ? body : undefined });
  if (!data) return;
  if (!data.ok) {
    if (!data.csrf_token) { window.location.href = '/game'; return; }
    return;
  }
  if (btn.dataset.redirect) { window.location.href = btn.dataset.redirect; return; }
  const g = await api('/game');
  populateStatusStrip(g);
  await applyNav();
}

// ── Boot ────────────────────────────────────────────────────────
async function loadGame() {
  const g = await api('/game');
  if (!g || !g.ok) return;
  populateStatusStrip(g);
  if (g.season_recap) {
    const resp = await fetch('/season/recap?_format=fragment');
    if (resp.status === 200) {
      document.getElementById('panel-primary').innerHTML = await resp.text();
      document.getElementById('panel-secondary').innerHTML = '';
      return;
    }
  }
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
  document.getElementById('unit-status').textContent = g.unit_status ?? '';
  document.getElementById('context-bar').textContent = '';
}

// ── Nav ──────────────────────────────────────────────────────────
async function applyNav(requestedView) {
  const headers = { Accept: 'application/json' };
  if (requestedView) headers['X-Nav-View'] = requestedView;
  const [navResp, gameResp] = await Promise.all([
    fetch('/nav', { headers }),
    fetch('/game', { headers: { Accept: 'application/json' } }),
  ]);
  const nav = await navResp.json();
  const g = await gameResp.json();
  populateStatusStrip(g);
  if (g.season_recap) {
    const resp = await fetch('/season/recap?_format=fragment');
    if (resp.status === 200) {
      document.getElementById('panel-primary').innerHTML = await resp.text();
      document.getElementById('panel-secondary').innerHTML = '';
      renderNavBar(nav.tabs);
      document.getElementById('context-bar').textContent = nav.context || '';
      return;
    }
  }
  renderNavBar(nav.tabs);
  document.getElementById('context-bar').textContent = nav.context || '';
  await Promise.all([
    fetchThenRender(nav.primary_fragment_url, 'panel-primary'),
    fetchThenRender(nav.secondary_fragment_url, 'panel-secondary'),
  ]);
}

function renderNavBar(tabs) {
  const bar = document.getElementById('nav-bar');
  bar.innerHTML = tabs.map(t => {
    const extras = t.action_url ? ` data-action-url="${t.action_url}" data-method="POST"` : '';
    const cls = `nav-btn${t.active ? ' active' : ' inactive'}${t.current ? ' current' : ''}`;
    return `<button class="${cls}" data-view="${t.id}"${t.reason ? ` title="${t.reason}"` : ''}${extras}>${t.label}</button>`;
  }).join('');
}

async function fetchThenRender(url, targetId) {
  if (!url) { document.getElementById(targetId).innerHTML = ''; return; }
  const resp = await fetch(url);
  if (resp.status === 204) { document.getElementById(targetId).innerHTML = ''; return; }
  const html = await resp.text();
  document.getElementById(targetId).innerHTML = html;
}

// ── Event delegation ─────────────────────────────────────────────
document.getElementById('nav-bar').addEventListener('click', async (e) => {
  const btn = e.target.closest('.nav-btn');
  if (!btn || btn.classList.contains('inactive')) return;
  if (btn.dataset.actionUrl) { await handleAction(btn); return; }
  applyNav(btn.dataset.view);
});

document.getElementById('panel-secondary').addEventListener('click', async (e) => {
  const link = e.target.closest('.season-recap-link');
  if (link) {
    e.preventDefault();
    const url = link.dataset.actionUrl;
    if (!url) return;
    const resp = await fetch(url);
    if (resp.status !== 200) return;
    document.getElementById('panel-primary').innerHTML = await resp.text();
    return;
  }
  const btn = e.target.closest('[data-action-url]');
  if (btn) handleAction(btn);
});

document.getElementById('panel-primary').addEventListener('click', async (e) => {
  const link = e.target.closest('.season-recap-link');
  if (link) {
    e.preventDefault();
    const url = link.dataset.actionUrl;
    if (!url) return;
    const resp = await fetch(url);
    if (resp.status !== 200) return;
    document.getElementById('panel-primary').innerHTML = await resp.text();
    return;
  }
  const ref = e.target.closest('[data-reference-id]');
  if (ref) {
    const id = ref.dataset.referenceId;
    const resp = await fetch(`/reference/${id}?_format=fragment`);
    if (resp.status !== 200) return;
    document.getElementById('panel-primary').innerHTML = await resp.text();
    return;
  }
  const btn = e.target.closest('[data-action-url]');
  if (btn) handleAction(btn);
});

loadGame();
