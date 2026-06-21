let G = {};

async function api(path, { body, method } = {}) {
  if (!method) method = body ? 'POST' : 'GET';
  const resp = await fetch(path, {
    method,
    headers: { Accept: 'application/json', ...(body ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return resp.json();
}

async function loadGame() {
  G = await api('/game');
  render();
}

function render() {
  const p = G.player || {};
  document.getElementById('player-name').textContent = p.name || '—';
  document.getElementById('stat-score').textContent = p.score ?? '—';
  document.getElementById('stat-scrap').textContent = p.scrap ?? '—';
  document.getElementById('stat-ap').textContent = p.action_points ?? '—';

  const s = G.season || {};
  document.getElementById('season-info').textContent =
    s.total_days ? `Day ${s.day} of ${s.total_days}` : 'No active season.';

  const msg = G.world_message;
  document.getElementById('crier-text').textContent =
    msg || 'The crier surveys the Bazaar. All is quiet.';

  renderActionCard();
  renderShed();
  renderSkills();
  renderLeaderboard();
}

function renderActionCard() {
  const card = document.getElementById('action-card');
  if (G.market_visit) {
    card.innerHTML = renderMarketVisit();
  } else if (G.prospecting) {
    card.innerHTML = renderProspecting();
  } else {
    card.innerHTML = renderIdle();
  }
  wireActionButtons();
}

function renderIdle() {
  const ap = G.player?.action_points ?? 0;
  if (ap < 1) {
    return `<div class="card mb-3"><div class="card-header">Actions</div><div class="card-body text-center"><p class="text-muted mb-0">No AP remaining today.</p></div></div>`;
  }
  return `<div class="card mb-3"><div class="card-header">Actions</div><div class="card-body text-center">
    <div class="d-grid gap-2">
      ${ap >= 2 ? '<button class="btn btn-success" id="btn-begin">Begin Expedition (2 AP)</button>' : ''}
      <button class="btn btn-info" id="btn-market">Visit Market (1 AP)</button>
    </div>
  </div></div>`;
}

function renderProspecting() {
  const a = G.prospecting;
  const stageCls = a.stage === 'stable' ? 'bg-success' : a.stage === 'strained' ? 'bg-warning text-dark' : 'bg-danger';
  return `<div class="card mb-3"><div class="card-header">Prospecting</div><div class="card-body">
    <p class="mb-1"><strong>${a.id || '—'}</strong></p>
    ${a.intro ? `<p class="mb-1 text-muted">${a.intro}</p>` : ''}
    <p class="mb-1">Value: <strong>${a.value ?? '—'}</strong></p>
    <p class="mb-1">Stage: <span class="badge ${stageCls}">${a.stage || '—'}</span></p>
    ${a.signal ? `<p class="mb-3 fst-italic">${a.signal}</p>` : ''}
    <div class="d-grid gap-2 d-md-flex">
      <button class="btn btn-primary" id="btn-push">Push</button>
      <button class="btn btn-warning" id="btn-stop">Stop</button>
    </div>
  </div></div>`;
}

function renderMarketVisit() {
  const m = G.market_visit;
  const c = m.customer || {};
  return `<div class="card mb-3"><div class="card-header">Market Visit</div><div class="card-body">
    <p class="mb-1">Customer: <strong>${c.faction_name || '—'}</strong></p>
    <p class="mb-1 text-muted">${c.disposition || ''}</p>
    ${m.irritation != null ? `<p class="mb-3 text-muted">Irritation: ${m.irritation}</p>` : ''}
    <p class="mb-2">Select an artifact to offer:</p>
    <div id="offer-items"></div>
    <div class="d-grid mt-2">
      <button class="btn btn-secondary" id="btn-send-away">Send Away</button>
    </div>
  </div></div>`;
}

function renderShed() {
  const items = G.shed || [];
  const container = document.getElementById('shed-items');
  const empty = document.getElementById('shed-empty');
  if (items.length === 0) {
    container.innerHTML = '';
    empty.style.display = '';
    return;
  }
  empty.style.display = 'none';
  container.innerHTML = items.map(item => {
    const condCls = item.condition === 'fresh' ? 'bg-success' : item.condition === 'settling' ? 'bg-warning text-dark' : 'bg-secondary';
    const offerBtn = G.market_visit
      ? `<button class="btn btn-sm btn-outline-primary offer-btn" data-id="${item.id}">Offer</button>`
      : '';
    return `<div class="d-flex justify-content-between align-items-center border-bottom py-2">
      <div>
        <strong>${item.artifact_id}</strong>
        <span class="badge ${condCls} ms-2">${item.condition}</span>
        <small class="text-muted d-block">${item.estimated_value_min}-${item.estimated_value_max} scrap · day ${item.days_in_shed}</small>
      </div>
      ${offerBtn}
    </div>`;
  }).join('');

  if (G.market_visit) {
    document.querySelectorAll('.offer-btn').forEach(btn => {
      btn.addEventListener('click', () => offerItem(btn.dataset.id));
    });
  }
}

function renderSkills() {
  const p = G.player || {};
  const scrap = p.scrap ?? 0;
  const container = document.getElementById('skills-body');

  api('/skills').then(data => {
    const skills = data.skills || [];
    container.innerHTML = skills.map(s => {
      const cur = s.current_level ?? 0;
      const max = s.max_level ?? 3;
      const atMax = cur >= max;
      const nextCost = atMax ? null : (s.levels?.[cur]?.cost ?? null);
      const canAfford = nextCost != null && scrap >= nextCost;
      const buyBtn = (!atMax && nextCost != null)
        ? `<button class="btn btn-sm ${canAfford ? 'btn-primary' : 'btn-outline-secondary'}" data-skill="${s.id}" ${!canAfford ? 'disabled' : ''}>Upgrade (${nextCost} scrap)</button>`
        : atMax ? '<span class="text-muted small">MAX</span>' : '';
      return `<div class="d-flex justify-content-between align-items-center border-bottom py-2">
        <div>
          <strong>${s.name}</strong>
          <span class="badge bg-info ms-2">${cur}/${max}</span>
          <small class="text-muted d-block">${s.description || ''}</small>
        </div>
        ${buyBtn}
      </div>`;
    }).join('');

    container.querySelectorAll('[data-skill]').forEach(btn => {
      btn.addEventListener('click', () => purchaseSkill(btn.dataset.skill));
    });
  });
}

function wireActionButtons() {
  document.getElementById('btn-begin')?.addEventListener('click', beginProspecting);
  document.getElementById('btn-push')?.addEventListener('click', pushArtifact);
  document.getElementById('btn-stop')?.addEventListener('click', stopProspecting);
  document.getElementById('btn-market')?.addEventListener('click', beginMarket);
  document.getElementById('btn-send-away')?.addEventListener('click', sendAway);
}

async function beginProspecting() {
  const data = await api('/prospecting/begin', { method: 'POST' });
  if (data.ok) await loadGame();
}

async function pushArtifact() {
  const data = await api('/prospecting/push', { method: 'POST' });
  if (data.ok) {
    if (data.artifact) {
      G.prospecting = data.artifact;
      G.player = data.player;
      renderActionCard();
      renderShed();
      updateStats();
    } else {
      await loadGame();
    }
  }
}

async function stopProspecting() {
  const data = await api('/prospecting/stop', { method: 'POST' });
  if (data.ok) await loadGame();
}

async function beginMarket() {
  const data = await api('/market/begin', { method: 'POST' });
  if (data.ok) await loadGame();
}

async function offerItem(shedItemId) {
  const data = await api('/market/offer', { body: { shed_item_id: shedItemId }, method: 'POST' });
  if (data.ok) await loadGame();
}

async function sendAway() {
  const data = await api('/market/send_away', { method: 'POST' });
  if (data.ok) await loadGame();
}

async function purchaseSkill(skillId) {
  const data = await api('/skills/purchase', { body: { skill_id: skillId }, method: 'POST' });
  if (data.ok) await loadGame();
}

function updateStats() {
  const p = G.player || {};
  document.getElementById('stat-score').textContent = p.score ?? '—';
  document.getElementById('stat-scrap').textContent = p.scrap ?? '—';
  document.getElementById('stat-ap').textContent = p.action_points ?? '—';
}

function renderLeaderboard() {
  const container = document.getElementById('leaderboard-body');
  api('/leaderboard').then(data => {
    const entries = data.leaderboard || [];
    if (entries.length === 0) {
      container.innerHTML = '<p class="text-muted text-center mb-0">No rankings yet.</p>';
      return;
    }
    container.innerHTML = entries.map(e =>
      `<div class="d-flex justify-content-between align-items-center border-bottom py-1">
        <span><strong>#${e.rank}</strong> ${e.name}</span>
        <span class="text-muted">${e.score}</span>
      </div>`
    ).join('');
  });
}

document.getElementById('delete-account-btn').addEventListener('click', async () => {
  if (!confirm('Delete your account permanently? This cannot be undone.')) return;
  const resp = await fetch('/player', { method: 'DELETE' });
  const data = await resp.json();
  if (data.ok) window.location.href = '/login';
});

loadGame();
