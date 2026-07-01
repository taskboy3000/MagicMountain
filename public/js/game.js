let CSRF_TOKEN = '';

// ── Audio: procedural keyboard click ────────────────────────────
let _audioCtx = null;
let _muted = false;  // initialized from server toggle state

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

function playSale() {
  if (_muted) return;
  const ctx = _initAudio();
  const now = ctx.currentTime;

  const notes = [523, 659, 784, 1047];
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

function playStop() {
  if (_muted) return;
  const ctx = _initAudio();
  const now = ctx.currentTime;

  for (let i = 0; i < 2; i++) {
    const t = now + i * 0.25;
    const vol = i === 0 ? 0.07 : 0.035;
    const osc = ctx.createOscillator();
    osc.type = 'triangle';
    osc.frequency.setValueAtTime(294, t);                       // D4
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.001, t);
    g.gain.linearRampToValueAtTime(vol, t + 0.008);
    g.gain.exponentialRampToValueAtTime(0.001, t + 0.25);
    osc.connect(g); g.connect(ctx.destination);
    osc.start(t); osc.stop(t + 0.25);
  }
}

function playFail() {
  if (_muted) return;
  const ctx = _initAudio();
  const now = ctx.currentTime;

  const osc = ctx.createOscillator();
  osc.type = 'sawtooth';
  osc.frequency.setValueAtTime(196, now);
  osc.frequency.exponentialRampToValueAtTime(73, now + 0.35);

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

function applyMuteState(muted) {
  _muted = !!muted;
  if (!_muted) _initAudio();
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

// ── Generic action handler (POST + JSON) ──────────────────────────
async function handleAction(btn) {
  const actionUrl = btn.dataset.actionUrl;
  if (!actionUrl) return;
  if (btn.dataset.confirm && !confirm(btn.dataset.confirm)) return;
  const method = btn.dataset.method || 'POST';
  const body = {};
  for (const key of Object.keys(btn.dataset)) {
    if (key === 'actionUrl' || key === 'method' || key === 'confirm' || key === 'redirect' || key === 'toggle') continue;
    body[key.replace(/([A-Z])/g, '_$1').toLowerCase()] = btn.dataset[key];
  }
  const data = await api(actionUrl, { method, body: Object.keys(body).length ? body : undefined });
  if (!data) return;
  if (!data.ok) { window.location.href = '/game'; return; }
  if (data.result === 'sold' || data.result === 'sold_more' || data.result === 'breakthrough') playSale();
  if (data.result === 'collapse' || data.result === 'sent_away' || data.result === 'customer_left' || data.result === 'over_budget') playFail();
  if (data.result === 'stopped') playStop();
  if (data.result === 'pressure_applied') playStop();
  if (btn.dataset.redirect) { window.location.href = btn.dataset.redirect; return; }
  const g = await api('/game');
  populateStatusStrip(g);
  // If toggle response includes tabs, re-render navs
  if (data.primary_tabs) { renderNav(data.primary_tabs, 'primary-nav'); renderNav(data.secondary_tabs || [], 'secondary-nav'); setMuteFromTabs(data.secondary_tabs); }
  if (data.context !== undefined) document.getElementById('context-bar').textContent = data.context || '';
  await applyNav();
}

// ── Generic fragment fetch (GET + HTML into target) ──────────────
async function handleFragmentFetch(btn) {
  const url = btn.dataset.fragmentUrl;
  const target = btn.dataset.target || 'secondary-content';
  if (!url) return;
  const resp = await fetch(url);
  if (resp.status === 200) {
    document.getElementById(target).innerHTML = await resp.text();
  }
}

// ── Boot ────────────────────────────────────────────────────────
async function loadGame() {
  const g = await api('/game');
  if (!g || !g.ok) return;
  populateStatusStrip(g);
  if (g.season_recap) {
    const resp = await fetch('/season/recap?_format=fragment');
    if (resp.status === 200) {
      document.getElementById('primary-content').innerHTML = await resp.text();
      document.getElementById('secondary-content').innerHTML = '';
      return;
    }
  }
  if (g.onboarding_notices && g.onboarding_notices.length) {
    const id = g.onboarding_notices[0];
    const resp = await fetch(`/onboarding/notice?notice=${encodeURIComponent(id)}&_format=fragment`);
    if (resp.status === 200) {
      document.getElementById('primary-content').innerHTML = await resp.text();
      document.getElementById('secondary-content').innerHTML = '';
    }
    return;
  }
  if (g.show_orientation) {
    const resp = await fetch('/orientation?_format=fragment');
    if (resp.status === 200) {
      document.getElementById('primary-content').innerHTML = await resp.text();
      document.getElementById('secondary-content').innerHTML = '';
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
      document.getElementById('primary-content').innerHTML = await resp.text();
      document.getElementById('secondary-content').innerHTML = '';
      renderNav(nav.primary_tabs, 'primary-nav');
      renderNav(nav.secondary_tabs || [], 'secondary-nav');
      setMuteFromTabs(nav.secondary_tabs);
      document.getElementById('context-bar').textContent = nav.context || '';
      return;
    }
  }
  renderNav(nav.primary_tabs, 'primary-nav');
  renderNav(nav.secondary_tabs || [], 'secondary-nav');
  setMuteFromTabs(nav.secondary_tabs);
  document.getElementById('context-bar').textContent = nav.context || '';
  await Promise.all([
    fetchThenRender(nav.primary_fragment_url, 'primary-content'),
    fetchThenRender(nav.secondary_fragment_url, 'secondary-content'),
  ]);
}

function renderNav(tabs, containerId) {
  const bar = document.getElementById(containerId);
  if (!bar) return;
  bar.innerHTML = tabs.map(t => {
    let html = `<button class="nav-btn${t.active ? ' active' : ' inactive'}${t.current ? ' current' : ''}" data-view="${t.id}"`;
    if (t.fragment_url) html += ` data-fragment-url="${t.fragment_url}"`;
    if (t.action_url)   html += ` data-action-url="${t.action_url}"`;
    if (t.method)       html += ` data-method="${t.method}"`;
    if (t.target)       html += ` data-target="${t.target}"`;
    if (t.key)          html += ` data-key="${t.key}"`;
    if (t.reason)       html += ` title="${t.reason}"`;
    html += `>${t.label_live || t.label}</button>`;
    return html;
  }).join('');
}

function setMuteFromTabs(tabs) {
  if (!tabs) return;
  const mute = tabs.find(t => t.key === 'mute');
  if (mute) applyMuteState(mute.toggle_state);
}

async function fetchThenRender(url, targetId) {
  if (!url) { document.getElementById(targetId).innerHTML = ''; return; }
  const resp = await fetch(url);
  if (resp.status === 204) { document.getElementById(targetId).innerHTML = ''; return; }
  const html = await resp.text();
  document.getElementById(targetId).innerHTML = html;
}

// ── Event delegation ─────────────────────────────────────────────
document.getElementById('primary-nav').addEventListener('click', async (e) => {
  const btn = e.target.closest('.nav-btn');
  if (!btn || btn.classList.contains('inactive')) return;
  e.stopPropagation();
  playClick();
  if (btn.dataset.actionUrl) { await handleAction(btn); return; }
  if (btn.dataset.fragmentUrl) { await handleFragmentFetch(btn); return; }
  applyNav(btn.dataset.view);
});

document.getElementById('secondary-nav').addEventListener('click', async (e) => {
  const btn = e.target.closest('.nav-btn');
  if (!btn || btn.classList.contains('inactive')) return;
  e.stopPropagation();
  playClick();
  if (btn.dataset.actionUrl) { await handleAction(btn); return; }
  if (btn.dataset.fragmentUrl) {
    // Move current marker from primary tabs to this secondary tab.
    document.querySelectorAll('#primary-nav .nav-btn.current')
      .forEach(el => el.classList.remove('current'));
    document.querySelectorAll('#secondary-nav .nav-btn.current')
      .forEach(el => el.classList.remove('current'));
    btn.classList.add('current');
    await handleFragmentFetch(btn);
    return;
  }
});

document.getElementById('secondary-content').addEventListener('click', async (e) => {
  const view = e.target.closest('[data-view]');
  if (view && !view.closest('.season-recap-link')) {
    e.preventDefault();
    if (view.dataset.view) { applyNav(view.dataset.view); return; }
  }
  const link = e.target.closest('.season-recap-link');
  if (link) {
    e.preventDefault();
    const url = link.dataset.actionUrl;
    if (!url) return;
    const resp = await fetch(url);
    if (resp.status !== 200) return;
    document.getElementById('primary-content').innerHTML = await resp.text();
    return;
  }
  const ref = e.target.closest('[data-reference-id]');
  if (ref) {
    const id = ref.dataset.referenceId;
    const resp = await fetch(`/reference/${id}?_format=fragment`);
    if (resp.status !== 200) return;
    document.getElementById('secondary-content').innerHTML = await resp.text();
    return;
  }
  const btn = e.target.closest('[data-action-url]');
  if (btn) { playClick(); handleAction(btn); }
});

document.getElementById('primary-content').addEventListener('click', async (e) => {
  const link = e.target.closest('.season-recap-link');
  if (link) {
    e.preventDefault();
    const url = link.dataset.actionUrl;
    if (!url) return;
    const resp = await fetch(url);
    if (resp.status !== 200) return;
    document.getElementById('primary-content').innerHTML = await resp.text();
    return;
  }
  const ref = e.target.closest('[data-reference-id]');
  if (ref) {
    const id = ref.dataset.referenceId;
    const resp = await fetch(`/reference/${id}?_format=fragment`);
    if (resp.status !== 200) return;
    document.getElementById('secondary-content').innerHTML = await resp.text();
    return;
  }
  const btn = e.target.closest('[data-action-url]');
  if (btn) { playClick(); handleAction(btn); }
});

loadGame();
