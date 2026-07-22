'use strict';

function initLogin() {
  const loginForm = document.getElementById('login-form');
  if (!loginForm) return;

  loginForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const nameInput = document.getElementById('display-name');
    const name = nameInput ? nameInput.value.trim() : '';
    const errEl = document.getElementById('error-msg');
    errEl.style.display = 'none';
    if (!name) return;

    const body = { displayName: name };
    const resp = await fetch(loginForm.action, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
      body: JSON.stringify(body)
    });
    const data = await resp.json();

    if (!data.ok) {
      if (data.need_token) {
        showTokenPrompt(data.token_prompt_url);
        return;
      }
      errEl.textContent = data.error || 'Login failed';
      errEl.style.display = 'block';
      return;
    }

    if (data.show_credentials) {
      showCredentials(data.new_credentials_url);
      return;
    }

    if (typeof window.stopAmbient === 'function') window.stopAmbient(500);
    window.location.href = data.game_url;
  });
}

async function showTokenPrompt(url) {
  const panel = document.getElementById('panel-primary');
  if (!url || !panel) return;

  const resp = await fetch(url);
  panel.innerHTML = await resp.text();

  panel.querySelector('#token-form')?.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const tokenInput = document.getElementById('token-input');
    const errEl = document.getElementById('token-error');
    const token = tokenInput ? tokenInput.value.trim() : '';
    if (!token) return;

    const form = ev.target;
    const resp = await fetch(form.action, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
      body: JSON.stringify({ displayName: form.dataset.displayName, token })
    });
    const data = await resp.json();
    if (!data.ok) {
      errEl.textContent = data.error || 'Invalid token';
      errEl.style.display = 'block';
      return;
    }
    if (typeof window.stopAmbient === 'function') window.stopAmbient(500);
    window.location.href = document.body.dataset.gameUrl;
  });
}

async function showRecoveryForm(url) {
  const panel = document.getElementById('panel-primary');
  if (!url || !panel) return;

  const resp = await fetch(url);
  panel.innerHTML = await resp.text();

  panel.querySelector('#recovery-form')?.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const input = document.getElementById('recovery-input');
    const errEl = document.getElementById('recovery-error');
    const code = input ? input.value.trim() : '';
    if (!code) return;

    const form = ev.target;
    const resp = await fetch(form.action, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
      body: JSON.stringify({ displayName: form.dataset.displayName, recoveryCode: code })
    });
    const data = await resp.json();
    if (!data.ok) {
      errEl.textContent = data.error || 'Invalid recovery code';
      errEl.style.display = 'block';
      return;
    }
    showCredentials(data.new_credentials_url);
  });
}

async function showCredentials(url) {
  const panel = document.getElementById('panel-primary');
  if (!url || !panel) return;

  const resp = await fetch(url);
  if (resp.status === 204) {
    if (typeof window.stopAmbient === 'function') window.stopAmbient(500);
    window.location.href = document.body.dataset.gameUrl;
    return;
  }
  panel.innerHTML = await resp.text();
}

function initPanelClicks() {
  const panel = document.getElementById('panel-primary');
  if (!panel) return;

  panel.addEventListener('click', (ev) => {
    if (ev.target.id === 'forgot-token-link') showRecoveryForm(ev.target.dataset.fragmentUrl);
    if (ev.target.id === 'back-to-token-link') showTokenPrompt(ev.target.dataset.fragmentUrl);
    if (ev.target.id === 'continue-btn') {
      if (typeof window.stopAmbient === 'function') window.stopAmbient(500);
      window.location.href = ev.target.dataset.gameUrl;
    }
  });
}

function initialization() {
  initLogin();
  initPanelClicks();
}

document.addEventListener('DOMContentLoaded', () => {
  initialization();
});
