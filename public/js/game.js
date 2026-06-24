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

async function loadGame() {
  G = await api('/game');
  render();
  renderPlayerFragment();
}

async function renderPlayerFragment() {
  const resp = await fetch('/player?_format=fragment');
  if (resp.status === 204) return;
  const html = await resp.text();
  document.getElementById('slot-player').innerHTML = html;
}

function render() {
  const p = G.player || {};
  document.getElementById('player-name').textContent = p.name || '—';
  document.getElementById('stat-score').textContent = p.score ?? '—';
  document.getElementById('stat-scrap').textContent = p.scrap ?? '—';
  document.getElementById('stat-ap').textContent = p.action_points ?? '—';

  const s = G.season || {};
  document.getElementById('season-info').textContent =
    s.total_days ? `${s.label} — Day ${s.day} of ${s.total_days}` : 'No active season.';

  renderRecap();
  renderActionCard();
  renderActionFragment();
  renderCrierFragment();
  renderShedFragment();
  renderSkillsFragment();
  renderFactionsFragment();
  renderLeaderboardFragment();
}

function renderRecap() {
  const recap = G.season_recap;
  if (!recap) return;
  const card = document.getElementById('action-card');
  const hl = recap.highlights || {};
  const st = recap.standing || {};
  const factions = Object.keys(st).length;
  card.innerHTML = `<div style="border:1px solid var(--mm-amber);margin-bottom:0.75rem">
    <div style="border-bottom:1px solid var(--mm-amber);padding:0.4rem 0.6rem;color:var(--mm-amber);font-size:0.8rem;text-transform:uppercase;letter-spacing:0.1em">${recap.label} — Final Results</div>
    <div style="padding:0.5rem 0.6rem">
      <div style="display:flex;text-align:center;margin-bottom:0.75rem">
        <div style="flex:1"><h5 style="margin:0 0 0.2rem 0;font-weight:400;font-size:0.9rem">Score</h5><span style="font-size:1.2rem">${recap.final_score}</span></div>
        <div style="flex:1"><h5 style="margin:0 0 0.2rem 0;font-weight:400;font-size:0.9rem">Rank</h5><span style="font-size:1.2rem">#${recap.rank}</span></div>
        <div style="flex:1"><h5 style="margin:0 0 0.2rem 0;font-weight:400;font-size:0.9rem">Scrap</h5><span style="font-size:1.2rem">${recap.final_scrap}</span></div>
      </div>
      <p style="margin:0 0 0.2rem 0;color:var(--mm-text-dim);font-size:0.78rem">Artifacts sold: ${hl.total_sales ?? 0}</p>
      <p style="margin:0 0 0.2rem 0;color:var(--mm-text-dim);font-size:0.78rem">Top sale: ${hl.top_sale_value ?? 0} scrap</p>
      <p style="margin:0 0 0.2rem 0;color:var(--mm-text-dim);font-size:0.78rem">Factions traded with: ${factions}</p>
      ${hl.evolved_artifacts_sold ? `<p style="margin:0 0 0.2rem 0;color:var(--mm-text-dim);font-size:0.78rem">Evolved artifacts sold: ${hl.evolved_artifacts_sold}</p>` : ''}
      <hr style="border:none;border-top:1px solid var(--mm-border)">
      <p style="color:var(--mm-text-dim);font-size:0.78rem;margin:0;font-style:italic"><em>A new season begins...</em></p>
    </div>
  </div>`;
}

function renderActionCard() {
  const card = document.getElementById('action-card');
  if (G.market_visit || G.prospecting) {
    card.innerHTML = '<div class="card mb-3"><div class="card-header">Activity in Progress</div><div class="card-body text-center"><div class="mm-skeleton" style="width:60%"></div><div class="mm-skeleton" style="width:40%"></div></div></div>';
  } else {
    card.innerHTML = renderIdle();
  }
  wireActionButtons();
}

async function renderProspectingFragment() {
  const resp = await fetch('/prospecting?_format=fragment');
  if (resp.status === 204) {
    document.getElementById('slot-action').innerHTML = '';
    return;
  }
  const html = await resp.text();
  document.getElementById('slot-action').innerHTML = html;
}

function renderIdle() {
  const ap = G.player?.action_points ?? 0;
  const hasItems = (G.shed?.length ?? 0) > 0;
  if (ap < 1) {
    return `<div style="border:1px solid var(--mm-border);margin-bottom:0.75rem"><div style="border-bottom:1px solid var(--mm-border);padding:0.4rem 0.6rem;color:var(--mm-amber);font-size:0.8rem;text-transform:uppercase;letter-spacing:0.1em">Actions</div><div style="padding:0.5rem 0.6rem;text-align:center"><p style="color:var(--mm-text-dim);margin:0;font-size:0.78rem">No AP remaining today.</p></div></div>`;
  }
  return `<div style="border:1px solid var(--mm-border);margin-bottom:0.75rem"><div style="border-bottom:1px solid var(--mm-border);padding:0.4rem 0.6rem;color:var(--mm-amber);font-size:0.8rem;text-transform:uppercase;letter-spacing:0.1em">Actions</div><div style="padding:0.5rem 0.6rem;text-align:center">
    <div style="display:flex;flex-direction:column;gap:0.3rem;align-items:center">
      ${ap >= 2 ? '<button class="mm-btn mm-btn-primary" id="btn-begin">Begin Expedition (2 AP)</button>' : ''}
      ${hasItems ? '<button class="mm-btn mm-btn-primary" id="btn-market">Visit Market (1 AP)</button>' : '<p style="color:var(--mm-text-dim);font-size:0.78rem;margin:0">No artifacts in shed to sell.</p>'}
    </div>
  </div></div>`;
}

async function renderShedFragment() {
  const resp = await fetch('/shed?_format=fragment');
  if (resp.status === 204) {
    document.getElementById('slot-shed').innerHTML = '';
    return;
  }
  const html = await resp.text();
  document.getElementById('slot-shed').innerHTML = html;
}

async function renderMarketFragment() {
  const resp = await fetch('/market?_format=fragment');
  if (resp.status === 204) {
    document.getElementById('slot-action').innerHTML = '';
    return;
  }
  const html = await resp.text();
  document.getElementById('slot-action').innerHTML = html;
}

async function renderActionFragment() {
  let url;
  if (G.market_visit) url = '/market?_format=fragment';
  else if (G.prospecting) url = '/prospecting?_format=fragment';
  else url = '/idle?_format=fragment';
  const resp = await fetch(url);
  if (resp.status === 204) {
    document.getElementById('slot-action').innerHTML = '';
    return;
  }
  const html = await resp.text();
  document.getElementById('slot-action').innerHTML = html;
}

async function refetchFragments(keys) {
  const fetches = (keys || []).map(key => {
    if (key === 'prospecting') return renderProspectingFragment();
    if (key === 'market') return renderMarketFragment();
    if (key === 'player') return renderPlayerFragment();
    if (key === 'shed') return renderShedFragment();
    if (key === 'crier') return renderCrierFragment();
    if (key === 'skills') return renderSkillsFragment();
    if (key === 'factions') return renderFactionsFragment();
    if (key === 'leaderboard') return renderLeaderboardFragment();
  });
  await Promise.all(fetches);
}

async function renderCrierFragment() {
  const resp = await fetch('/crier?_format=fragment');
  if (resp.status === 204) {
    document.getElementById('slot-crier').innerHTML = '';
    return;
  }
  const html = await resp.text();
  document.getElementById('slot-crier').innerHTML = html;
}

async function renderSkillsFragment() {
  const resp = await fetch('/skills?_format=fragment');
  if (resp.status === 204) {
    document.getElementById('slot-skills').innerHTML = '';
    return;
  }
  const html = await resp.text();
  document.getElementById('slot-skills').innerHTML = html;
}

async function renderFactionsFragment() {
  const resp = await fetch('/factions?_format=fragment');
  if (resp.status === 204) {
    document.getElementById('slot-factions').innerHTML = '';
    return;
  }
  const html = await resp.text();
  document.getElementById('slot-factions').innerHTML = html;
}

async function renderLeaderboardFragment() {
  const resp = await fetch('/leaderboard?_format=fragment');
  if (resp.status === 204) {
    document.getElementById('slot-leaderboard').innerHTML = '';
    return;
  }
  const html = await resp.text();
  document.getElementById('slot-leaderboard').innerHTML = html;
}

function wireActionButtons() {
  document.getElementById('btn-begin')?.addEventListener('click', beginProspecting);
  document.getElementById('btn-push')?.addEventListener('click', pushArtifact);
  document.getElementById('btn-stop')?.addEventListener('click', stopProspecting);
  document.getElementById('btn-market')?.addEventListener('click', beginMarket);
  document.getElementById('btn-send-away')?.addEventListener('click', sendAway);
  document.getElementById('btn-accept-counter')?.addEventListener('click', acceptCounter);
}

async function beginProspecting() {
  const data = await api('/prospecting/begin', { method: 'POST' });
  if (!data.ok) return;
  if (data.player) Object.assign(G.player, data.player);
  if (data.artifact) G.prospecting = data.artifact;
  updateStats();
  renderActionCard();
  if (data.refetch) await refetchFragments(data.refetch);
}

async function pushArtifact() {
  const data = await api('/prospecting/push', { method: 'POST' });
  if (!data.ok) return;
  if (data.player) Object.assign(G.player, data.player);
  if (data.artifact) G.prospecting = data.artifact;
  else G.prospecting = null;
  updateStats();
  renderActionCard();
  if (data.refetch) await refetchFragments(data.refetch);
  else await loadGame();
}

async function stopProspecting() {
  const data = await api('/prospecting/stop', { method: 'POST' });
  if (data.ok) await loadGame();
}

async function beginMarket() {
  const data = await api('/market/begin', { method: 'POST' });
  if (!data.ok) return;
  if (data.player) Object.assign(G.player, data.player);
  G.market_visit = { customer: data.customer || {} };
  updateStats();
  renderActionCard();
  if (data.refetch) await refetchFragments(data.refetch);
  else await loadGame();
}

async function offerItem(shedItemId) {
  const data = await api('/market/offer', { body: { shed_item_id: shedItemId }, method: 'POST' });
  if (!data.ok) return;
  if (data.player) Object.assign(G.player, data.player);
  updateStats();
  if (data.result === 'sold' || data.result === 'customer_left' || data.result === 'sent_away') {
    G.market_visit = null;
    await loadGame();
    return;
  }
  if (data.refetch) await refetchFragments(data.refetch);
  else await loadGame();
}

async function sendAway() {
  const data = await api('/market/send_away', { method: 'POST' });
  if (!data.ok) return;
  G.market_visit = null;
  await loadGame();
}

async function acceptCounter() {
  const data = await api('/market/accept_counter', { method: 'POST' });
  if (!data.ok) return;
  if (data.player) Object.assign(G.player, data.player);
  updateStats();
  if (data.result === 'sold') {
    G.market_visit = null;
    await loadGame();
    return;
  }
  if (data.refetch) await refetchFragments(data.refetch);
  else await loadGame();
}

async function purchaseSkill(skillId) {
  const data = await api('/skills/purchase', { body: { skill_id: skillId }, method: 'POST' });
  if (!data.ok) return;
  if (data.player) Object.assign(G.player, data.player);
  updateStats();
  if (data.refetch) await refetchFragments(data.refetch);
  else await loadGame();
}

function updateStats() {
  const p = G.player || {};
  document.getElementById('stat-score').textContent = p.score ?? '—';
  document.getElementById('stat-scrap').textContent = p.scrap ?? '—';
  document.getElementById('stat-ap').textContent = p.action_points ?? '—';
}

document.getElementById('delete-account-btn').addEventListener('click', async () => {
  if (!confirm('Delete your account permanently? This cannot be undone.')) return;
  const data = await api('/player', { method: 'DELETE' });
  if (data.ok) window.location.href = '/login';
});

document.getElementById('btn-end-season')?.addEventListener('click', async () => {
  const data = await api('/season/end', { method: 'POST' });
  if (data.ok) await loadGame();
});

// Event delegation for shed offer buttons
document.getElementById('slot-shed').addEventListener('click', (e) => {
  const btn = e.target.closest('.offer-btn');
  if (btn) offerItem(btn.dataset.id);
});

// Event delegation for action buttons in fragment panels
document.getElementById('slot-action').addEventListener('click', (e) => {
  const id = e.target.id;
  if (id === 'btn-push') pushArtifact();
  else if (id === 'btn-stop') stopProspecting();
  else if (id === 'btn-begin') beginProspecting();
  else if (id === 'btn-market') beginMarket();
  else if (id === 'btn-send-away') sendAway();
  else if (id === 'btn-accept-counter') acceptCounter();
});

// Event delegation for skill purchase buttons
document.getElementById('slot-skills').addEventListener('click', (e) => {
  const btn = e.target.closest('.buy-skill-btn');
  if (btn) purchaseSkill(btn.dataset.skill);
});

loadGame();
