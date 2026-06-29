let CSRF_TOKEN = '';

// ── Audio: procedural keyboard click ────────────────────────────
let _audioCtx = null;
let _muted = localStorage.getItem('mm_muted') === '1';

function _initAudio() {
  if (_audioCtx) return _audioCtx;
  _audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  return _audioCtx;
}

function playClick() {
  if (_muted) return;
  const ctx = _initAudio();
  const now = ctx.currentTime;

  const v = () => 1 + (Math.random() - 0.5) * 0.15;

  // Subtle resonant lowpass with light variation
  const lp = ctx.createBiquadFilter();
  lp.type = 'lowpass';
  lp.frequency.setValueAtTime(5500 * v(), now);
  lp.Q.setValueAtTime(1.5 + Math.random() * 1.5, now);
  lp.connect(ctx.destination);

  const h = ctx.createOscillator();
  h.type = 'square';
  h.frequency.setValueAtTime(3200 * v(), now);
  h.frequency.exponentialRampToValueAtTime(800 * v(), now + 0.005);
  const hg = ctx.createGain();
  hg.gain.setValueAtTime(0.06 * v(), now);
  hg.gain.exponentialRampToValueAtTime(0.001, now + 0.008);
  h.connect(hg); hg.connect(lp);
  h.start(now); h.stop(now + 0.008);

  const l = ctx.createOscillator();
  l.type = 'sine';
  l.frequency.setValueAtTime(140 * v(), now);
  l.frequency.exponentialRampToValueAtTime(60, now + 0.015);
  const lg = ctx.createGain();
  lg.gain.setValueAtTime(0.10 * v(), now);
  lg.gain.exponentialRampToValueAtTime(0.001, now + 0.018);
  l.connect(lg); lg.connect(ctx.destination);
  l.start(now); l.stop(now + 0.018);
}

// ── Sale register ring ─────────────────────────────────────────
function playSale() {
  if (_muted) return;
  const ctx = _initAudio();
  const now = ctx.currentTime;

  const notes = [523, 659, 784, 1047]; // C5 E5 G5 C6
  const start = 0;
  const step = 0.065;
  const dur  = 0.14;

  for (let i = 0; i < notes.length; i++) {
    const t = now + start + i * step;
    const osc = ctx.createOscillator();
    osc.type = 'triangle';
    osc.frequency.setValueAtTime(notes[i], t);
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.001, t);
    g.gain.linearRampToValueAtTime(0.09, t + 0.01);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    osc.connect(g); g.connect(ctx.destination);
    osc.start(t); osc.stop(t + dur);
  }
}

// ── Failure tone ──────────────────────────────────────────────
function playFail() {
  if (_muted) return;
  const ctx = _initAudio();
  const now = ctx.currentTime;

  const osc = ctx.createOscillator();
  osc.type = 'sawtooth';
  osc.frequency.setValueAtTime(196, now);            // G3
  osc.frequency.exponentialRampToValueAtTime(73, now + 0.35); // D2

  const lp = ctx.createBiquadFilter();
  lp.type = 'lowpass';
  lp.frequency.setValueAtTime(800, now);
  lp.frequency.exponentialRampToValueAtTime(300, now + 0.35);

  const g = ctx.createGain();
  g.gain.setValueAtTime(0.001, now);
  g.gain.linearRampToValueAtTime(0.07, now + 0.02);
  g.gain.setValueAtTime(0.07, now + 0.08);
  g.gain.exponentialRampToValueAtTime(0.001, now + 0.40);

  osc.connect(lp); lp.connect(g); g.connect(ctx.destination);
  osc.start(now); osc.stop(now + 0.40);
}

function toggleMute() {
  _muted = !_muted;
  localStorage.setItem('mm_muted', _muted ? '1' : '0');
  _initAudio();
  if (!_muted) playClick();
  updateMuteButton();
}

function updateMuteButton() {
  const btn = document.getElementById('mute-btn');
  if (btn) btn.textContent = _muted ? '[)]' : ')))]';
}

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
  if (!data.ok) { window.location.href = '/game'; return; }
  if (data.result === 'sold' || data.result === 'sold_more' || data.result === 'breakthrough') playSale();
  if (data.result === 'collapse' || data.result === 'sent_away' || data.result === 'customer_left' || data.result === 'over_budget') playFail();
  if (btn.dataset.redirect) { window.location.href = btn.dataset.redirect; return; }
  const g = await api('/game');
  populateStatusStrip(g);
  await applyNav();
}

// ── Boot ────────────────────────────────────────────────────────
async function loadGame() {
  updateMuteButton();
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
  if (g.show_orientation) {
    const resp = await fetch('/orientation?_format=fragment');
    if (resp.status === 200) {
      document.getElementById('panel-primary').innerHTML = await resp.text();
      document.getElementById('panel-secondary').innerHTML = '';
    }
    return;
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
  if (gameResp.status === 401 || navResp.status === 401) {
    window.location.href = '/game';
    return;
  }
  const nav = await navResp.json();
  const g = await gameResp.json();
  if (!g.ok || !nav.ok) { window.location.href = '/game'; return; }
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
  playClick();
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
  const ref = e.target.closest('[data-reference-id]');
  if (ref) {
    const id = ref.dataset.referenceId;
    const resp = await fetch(`/reference/${id}?_format=fragment`);
    if (resp.status !== 200) return;
    document.getElementById('panel-secondary').innerHTML = await resp.text();
    return;
  }
  const btn = e.target.closest('[data-action-url]');
  if (btn) { playClick(); handleAction(btn); }
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
    document.getElementById('panel-secondary').innerHTML = await resp.text();
    return;
  }
  const btn = e.target.closest('[data-action-url]');
  if (btn) { playClick(); handleAction(btn); }
});

loadGame();
