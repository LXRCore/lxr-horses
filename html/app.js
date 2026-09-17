/* LXR-HORSES — Stable UI on the LXR UI Kit | © 2026 iBoss21 / LXRCore */
(function () {
  const $ = (id) => document.getElementById(id);
  const app = $('app');
  const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'lxr-horses';
  let D = null, L = {}, tab = 'owned';
  let sel = { owned: null, buy: null, tack: null, market: null };
  let buyForm = { name: '', gender: 'gelding', scale: 1.0 };
  let breedSel = { sire: null, dam: null };
  const STATS = ['speed', 'acceleration', 'health', 'stamina', 'handling', 'courage'];
  const CORES = ['health', 'stamina', 'hunger', 'thirst', 'cleanliness', 'mood'];

  const t = (k, vars) => { let s = L[k] || k.split('.').pop().replace(/_/g, ' '); if (vars) for (const v in vars) s = s.replace('%{' + v + '}', vars[v]); return s; };
  const money = (n) => (Math.round((n || 0) * 100) / 100).toFixed(2);
  const pad = (i) => String(i).padStart(2, '0');
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const post = (name, body) => fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) }).then(r => r.json()).catch(() => ({ ok: false }));

  let toastEl;
  function toast(msg, bad) {
    if (!toastEl) { toastEl = document.createElement('div'); toastEl.className = 'lxr-toast st-toast'; document.body.appendChild(toastEl); }
    toastEl.textContent = msg; toastEl.classList.toggle('is-bad', !!bad); toastEl.classList.toggle('is-ok', !bad); toastEl.classList.add('show');
    setTimeout(() => toastEl.classList.remove('show'), 2500);
  }
  function applyLocale() { document.querySelectorAll('[data-l]').forEach(el => { const k = 'ui.' + el.dataset.l; if (L[k]) el.textContent = L[k]; }); }
  function setTab(name) {
    tab = name;
    document.querySelectorAll('.st-tabs .lxr-chip').forEach(b => b.setAttribute('aria-pressed', b.dataset.tab === name ? 'true' : 'false'));
    document.querySelectorAll('.st-tab').forEach(s => s.classList.toggle('is-on', s.id === 'tab-' + name));
    render();
  }

  // ─── row builder (the kit's index row) ───
  function row(i, name, meta, price, opts) {
    opts = opts || {};
    const b = document.createElement('button');
    b.className = 'lxr-row lxr-row--sub' + (opts.active ? ' is-active' : '') + (opts.locked ? ' is-locked' : '');
    b.innerHTML = `<span class="lxr-row-index">${pad(i)}</span>
      <span class="lxr-row-body"><span class="lxr-row-name">${esc(name)}</span><span class="lxr-row-sub">${meta}</span></span>
      ${opts.badge ? `<span class="lxr-row-badge">${esc(opts.badge)}</span>` : ''}
      ${price != null ? `<span class="lxr-row-price lxr-num">${price}</span>` : ''}`;
    b.onclick = opts.onclick;
    return b;
  }

  function ownedList() {
    const box = $('owned-list'); box.innerHTML = '';
    if (!D.owned.length) { box.innerHTML = `<div class="st-note">${t('ui.no_horses')}</div>`; return; }
    D.owned.forEach((h, i) => {
      const meta = `${esc(h.breed)} · ${esc(h.coat)} · ${t('gender.' + h.gender)}${h.injured ? ' · <span class="lxr-t-blood">' + t('ui.injured') + '</span>' : ''}`;
      box.appendChild(row(i + 1, (h.favorite ? '★ ' : '') + h.name, meta, `${t('ui.bond')} ${h.bond}`, {
        active: sel.owned === h.id, locked: h.dead, badge: h.active ? t('ui.out') : (h.listing ? t('ui.listed') : null),
        onclick: () => { sel.owned = h.id; post('preview', { model: h.model, tack: h.tack, scale: h.scale }); render(); },
      }));
    });
  }

  function buyList() {
    const cls = $('buy-class'), br = $('buy-breed');
    const classes = [...new Set(D.stock.map(s => s.class))].sort();
    if (cls.options.length !== classes.length + 1) cls.innerHTML = `<option value="">${t('ui.all_classes')}</option>` + classes.map(c => `<option value="${c}">${t('class.' + c)}</option>`).join('');
    const breeds = [...new Set(D.stock.filter(s => !cls.value || s.class === cls.value).map(s => s.breed))].sort();
    const prev = br.value;
    br.innerHTML = `<option value="">${t('ui.all_breeds')}</option>` + breeds.map(b => `<option value="${esc(b)}">${esc(b)}</option>`).join('');
    if (breeds.includes(prev)) br.value = prev;
    const box = $('buy-list'); box.innerHTML = '';
    D.stock.filter(s => (!cls.value || s.class === cls.value) && (!br.value || s.breed === br.value)).forEach((s, i) => {
      box.appendChild(row(i + 1, `${s.breed} — ${s.coat}`, `${t('class.' + s.class)} · ${t('rarity.' + s.rarity)} · ${t('temper.' + s.temperament)}`, '$' + money(s.price), {
        active: sel.buy === s.model,
        onclick: () => { sel.buy = s.model; buyForm.name = s.coat; post('preview', { model: s.model, tack: {}, scale: buyForm.scale }); render(); },
      }));
    });
  }

  function tackList() {
    const slotSel = $('tack-slot');
    const slots = Object.keys(D.options.slots).sort((a, b) => D.options.slots[a].order - D.options.slots[b].order);
    if (slotSel.options.length !== slots.length) slotSel.innerHTML = slots.map(s => `<option value="${s}">${esc(D.options.slots[s].label)}</option>`).join('');
    const ownedOnly = $('tack-owned-only').checked;
    const owned = {}; D.ownedTack.forEach(r => { owned[r.piece] = (owned[r.piece] || 0) + 1; });
    const box = $('tack-list'); box.innerHTML = '';
    D.tack.filter(p => p.slot === slotSel.value && (!ownedOnly || owned[p.id])).forEach((p, i) => {
      const st = Object.entries(p.stats || {}).map(([k, v]) => `${t('stat.' + k)} +${v}`).join(' · ');
      box.appendChild(row(i + 1, p.label, `${t('ui.tier')} ${p.tier}${st ? ' · ' + st : ''}`, '$' + money(p.price), {
        active: sel.tack === p.id, badge: owned[p.id] ? '×' + owned[p.id] : null,
        onclick: () => { sel.tack = p.id; const h = D.owned.find(x => x.id === sel.owned) || D.owned[0]; if (h) { const tk = Object.assign({}, h.tack); tk[p.slot] = p.id; post('preview', { model: h.model, tack: tk, scale: h.scale }); } render(); },
      }));
    });
  }

  function marketList() {
    const box = $('market-list'); box.innerHTML = '';
    if (!D.market.length) { box.innerHTML = `<div class="st-note">${t('ui.no_listings')}</div>`; return; }
    D.market.forEach((h, i) => box.appendChild(row(i + 1, h.name, `${esc(h.breed)} · ${esc(h.coat)} · ${t('ui.bond')} ${h.bond} · ${esc(h.seller)}`, '$' + money(h.price), {
      active: sel.market === h.id, onclick: () => { sel.market = h.id; post('preview', { model: h.model, tack: h.tack, scale: h.scale }); render(); },
    })));
  }

  function breedBox() {
    const box = $('breed-box');
    if (!D.options.breeding) { box.innerHTML = `<div class="st-note">${t('ui.breeding_off')}</div>`; return; }
    const sires = D.owned.filter(h => h.gender === 'male' && !h.dead), dams = D.owned.filter(h => h.gender === 'female' && !h.dead);
    const opt = (list, cur) => `<option value="">—</option>` + list.map(h => `<option value="${h.id}" ${cur === h.id ? 'selected' : ''}>${esc(h.name)} (${t('ui.bond')} ${h.bond})</option>`).join('');
    const due = (D.breeding || []).length;
    box.innerHTML = `<div class="st-field"><span class="lxr-mono lxr-t-ash">${t('ui.sire')}</span><select class="lxr-input" id="breed-sire">${opt(sires, breedSel.sire)}</select></div>
      <div class="st-field"><span class="lxr-mono lxr-t-ash">${t('ui.dam')}</span><select class="lxr-input" id="breed-dam">${opt(dams, breedSel.dam)}</select></div>
      <p class="st-note">${t('ui.breed_note', { fee: money(D.options.breeding.fee), hours: D.options.breeding.gestationHours, bond: D.options.breeding.minBond })}</p>
      <div class="st-actions"><button class="lxr-btn" id="breed-go">${t('ui.breed')} — $${money(D.options.breeding.fee)}</button>
      <button class="lxr-btn-ghost" id="breed-collect" ${due ? '' : 'disabled'}>${t('ui.collect_foals')} (${due})</button></div>`;
    $('breed-sire').onchange = e => breedSel.sire = +e.target.value || null;
    $('breed-dam').onchange = e => breedSel.dam = +e.target.value || null;
    $('breed-go').onclick = async () => { if (!breedSel.sire || !breedSel.dam) return toast(t('error.bad_pair'), true); const r = await post('breed', { sire: breedSel.sire, dam: breedSel.dam }); if (r.ok) { D = r.data; toast(t('ui.bred')); render(); } else if (r.error) toast(t('error.' + r.error), true); };
    $('breed-collect').onclick = async () => { const r = await post('breed', { collect: true }); if (r.ok) { D = r.data; toast(t('ui.foal_collected')); render(); } else if (r.error) toast(t('error.' + r.error), true); };
  }

  // ─── detail panels ───
  const meter = (label, v, max, cls) => `<span class="lxr-mono lxr-t-ash">${label}</span><div class="lxr-meter"><div class="lxr-meter-fill ${cls || ''}" style="width:${Math.max(0, Math.min(100, v / max * 100))}%"></div></div><span class="lxr-num lxr-t-bone">${Math.round(v * 10) / 10}</span>`;
  const statBars = (s) => STATS.map(k => meter(t('stat.' + k), s[k] || 0, 10)).join('');
  const coreBars = (c) => CORES.map(k => meter(t('core.' + k), c[k] || 0, 100, (c[k] || 0) < 25 ? 'is-bad' : 'is-ok')).join('');
  const card = (inner) => `<div class="st-card lxr-rise">${inner}</div>`;

  function detailOwned() {
    const h = D.owned.find(x => x.id === sel.owned);
    if (!h) return card(`<p class="st-sub">${t('ui.pick_horse')}</p>`);
    const slots = Object.keys(D.options.slots).sort((a, b) => D.options.slots[a].order - D.options.slots[b].order);
    const tack = slots.map((s, i) => { const pid = h.tack[s]; const piece = pid ? D.tack.find(p => p.id === pid) : null;
      return `<div class="lxr-row lxr-row--compact"><span class="lxr-row-index">${pad(i + 1)}</span><span class="lxr-row-name">${esc(D.options.slots[s].label)}</span><span class="lxr-row-meta">${piece ? esc(piece.label) : (pid || '—')}</span></div>`; }).join('');
    const insured = h.insuredUntil && h.insuredUntil * 1000 > Date.now();
    return card(`<span class="lxr-mono lxr-t-blood">${esc(h.breed)} · ${esc(h.coat)}</span>
      <h2 class="lxr-cut">${esc(h.name)}</h2>
      <p class="st-sub">${t('gender.' + h.gender)} · ${t('personality')}: ${esc(h.personalityLabel || '')} · ${t('ui.age')} ${h.ageDays}${h.injured ? ' · <span class="lxr-t-blood">' + t('ui.injured') + '</span>' : ''}${h.dead ? ' · <span class="lxr-t-blood">' + t('ui.dead') + '</span>' : ''}</p>
      <div class="st-stats">${statBars(h.stats)}</div>
      <div class="st-stats">${coreBars(h.cores)}</div>
      <p class="st-note lxr-mono">${t('ui.bond')} ${h.bond} · ${Math.round(h.bondProgress * 100)}% · ${t('ui.shoes')} ${Math.round(h.shoesLeft)}h · ${insured ? t('ui.insured') : t('ui.uninsured')}</p>
      <div class="st-tack">${tack}</div>
      <div class="st-actions">
        <button class="lxr-btn" data-a="select" ${h.dead || h.injured || h.listing ? 'disabled' : ''}>${t('ui.take_out')}</button>
        <button class="lxr-btn-ghost" data-a="store" ${!h.active ? 'disabled' : ''}>${t('ui.store')}</button>
        <button class="lxr-btn-ghost" data-a="favorite">${h.favorite ? t('ui.unfavorite') : t('ui.favorite')}</button>
        <button class="lxr-btn-ghost" data-a="rename">${t('ui.rename')} · $${money(D.options.renamePrice)}</button>
        <button class="lxr-btn-ghost" data-a="insure" ${!D.options.insurance.enabled ? 'disabled' : ''}>${t('ui.insure')} · $${money(h.insurancePrice)}</button>
        <button class="lxr-btn-ghost" data-a="vet" ${!(h.injured || h.dead) ? 'disabled' : ''}>${t('ui.vet')} · $${money(h.dead ? D.options.insurance.revivePrice : D.options.vetPrice)}</button>
        ${h.listing ? `<button class="lxr-btn-ghost" data-a="unlist">${t('ui.unlist')}</button>` : `<button class="lxr-btn-ghost" data-a="list">${t('ui.list_market')}</button>`}
        <button class="lxr-btn-bad" data-a="sell" ${h.active || h.listing ? 'disabled' : ''}>${t('ui.sell')} · $${money(h.sellValue)}</button>
      </div>`);
  }

  function detailBuy() {
    const s = D.stock.find(x => x.model === sel.buy);
    if (!s) return card(`<p class="st-sub">${t('ui.pick_stock')}</p>`);
    const [lo, hi] = D.options.scaleRange;
    const g = D.options.genderChoice ? `<div class="st-field"><span class="lxr-mono lxr-t-ash">${t('ui.gender')}</span><div class="st-seg">${['male', 'female', 'gelding'].map(x => `<button class="lxr-chip" aria-pressed="${buyForm.gender === x}" data-g="${x}">${t('gender.' + x)}</button>`).join('')}</div></div>` : '';
    return card(`<span class="lxr-mono lxr-t-blood">${t('class.' + s.class)} · ${t('rarity.' + s.rarity)} · ${t('temper.' + s.temperament)} · ${t('ui.tier')} ${s.tier}</span>
      <h2 class="lxr-cut">${esc(s.breed)} <span class="lxr-cut-slant">${esc(s.coat)}</span></h2>
      <p class="st-desc">${esc(s.description || '')}</p>
      <div class="st-stats">${statBars(s.stats)}</div>
      <div class="st-field"><span class="lxr-mono lxr-t-ash">${t('ui.name')}</span><input class="lxr-input" type="text" id="buy-name" maxlength="24" value="${esc(buyForm.name)}"></div>
      ${g}
      <div class="st-field"><span class="lxr-mono lxr-t-ash" id="scale-label">${t('ui.size')} · ${buyForm.scale.toFixed(2)}</span><input type="range" id="buy-scale" min="${lo}" max="${hi}" step="0.01" value="${buyForm.scale}"></div>
      <div class="st-actions"><button class="lxr-btn" id="buy-go" ${D.count >= D.limit ? 'disabled' : ''}>${t('ui.buy')} · $${money(s.price)}</button><span class="st-note lxr-mono">${t('ui.owned_count', { n: D.count, max: D.limit })}</span></div>`);
  }

  function detailTack() {
    const p = D.tack.find(x => x.id === sel.tack);
    if (!p) return card(`<p class="st-sub">${t('ui.pick_tack')}</p>`);
    const owned = D.ownedTack.filter(r => r.piece === p.id), free = owned.filter(r => !r.horse_id).length;
    const h = D.owned.find(x => x.id === sel.owned);
    const st = Object.entries(p.stats || {}).map(([k, v]) => `${t('stat.' + k)} +${v}`).join(' · ') || t('ui.cosmetic');
    return card(`<span class="lxr-mono lxr-t-blood">${esc(D.options.slots[p.slot].label)} · ${t('ui.tier')} ${p.tier}</span>
      <h2 class="lxr-cut">${esc(p.label)}</h2>
      <p class="st-sub">${st}</p>
      <p class="st-note lxr-mono">${t('ui.tack_owned', { n: owned.length, free })}</p>
      <div class="st-actions">
        <button class="lxr-btn" data-t="buy">${t('ui.buy')} · $${money(p.price)}</button>
        <button class="lxr-btn-ghost" data-t="sell" ${free ? '' : 'disabled'}>${t('ui.sell')} · $${money(p.price * 0.5)}</button>
        <button class="lxr-btn-ghost" data-t="equip" ${(h && free) ? '' : 'disabled'}>${t('ui.equip_on', { name: h ? esc(h.name) : '…' })}</button>
        <button class="lxr-btn-ghost" data-t="unequip" ${(h && h.tack[p.slot]) ? '' : 'disabled'}>${t('ui.unequip')}</button>
      </div><p class="st-note">${t('ui.equip_pick')}</p>`);
  }

  function detailMarket() {
    const h = D.market.find(x => x.id === sel.market);
    if (!h) return card(`<p class="st-sub">${t('ui.pick_listing')}</p>`);
    return card(`<span class="lxr-mono lxr-t-blood">${esc(h.breed)} · ${esc(h.coat)} · ${t('ui.seller')}: ${esc(h.seller)}</span><h2 class="lxr-cut">${esc(h.name)}</h2>
      <p class="st-sub">${t('gender.' + h.gender)} · ${esc(h.personalityLabel || '')}</p>
      <div class="st-stats">${statBars(h.stats)}</div><div class="st-stats">${coreBars(h.cores)}</div>
      <div class="st-actions"><button class="lxr-btn" id="market-go" ${D.count >= D.limit ? 'disabled' : ''}>${t('ui.buy')} · $${money(h.price)}</button></div>`);
  }

  function wildBox() {
    const w = D.pendingWild;
    return card(`<span class="lxr-mono lxr-t-blood">${t('ui.pending_wild', { label: '' })}</span><h2 class="lxr-cut">${esc(w.label)}</h2><p class="st-sub">${t('ui.wild_pending')}</p>
      <div class="st-actions"><button class="lxr-btn" id="wild-claim">${t('ui.claim')} · $${money(w.fee)}</button><button class="lxr-btn-ghost" id="wild-sell">${t('ui.sell')} · $${money(w.sell)}</button></div>`);
  }

  function render() {
    if (!D) return;
    $('stable-name').textContent = D.stable.label;
    $('cash').textContent = money(D.cash);
    $('pending-wild').textContent = D.pendingWild ? t('ui.pending_wild', { label: D.pendingWild.label }) : '';
    ownedList(); buyList(); tackList(); marketList(); breedBox();
    $('detail').innerHTML = tab === 'owned' ? detailOwned() : tab === 'buy' ? detailBuy() : tab === 'tack' ? detailTack() : tab === 'market' ? detailMarket() : (D.pendingWild ? wildBox() : '');
    if (tab !== 'breed' && D.pendingWild && tab === 'owned' && !sel.owned) $('detail').innerHTML = wildBox();
    bind();
  }

  function bind() {
    document.querySelectorAll('[data-a]').forEach(b => b.onclick = async () => {
      const a = b.dataset.a; let arg;
      if (a === 'rename') { arg = prompt(t('ui.rename_prompt')); if (!arg) return; }
      if (a === 'list') { arg = parseFloat(prompt(t('ui.list_prompt', { min: D.options.market.minPrice, max: D.options.market.maxPrice }))); if (!arg) return; }
      if (a === 'sell' && !confirm(t('ui.sell_confirm'))) return;
      const r = a === 'sell' ? await post('sell', { id: sel.owned }) : await post('action', { action: a, id: sel.owned, arg });
      if (r.ok && r.data) { D = r.data; render(); toast(t('ui.done')); } else if (!r.ok && r.error) toast(t('error.' + r.error), true);
    });
    document.querySelectorAll('[data-g]').forEach(b => b.onclick = () => { buyForm.gender = b.dataset.g; render(); });
    const nameEl = $('buy-name'); if (nameEl) nameEl.oninput = e => buyForm.name = e.target.value;
    const scaleEl = $('buy-scale'); if (scaleEl) scaleEl.oninput = e => { buyForm.scale = parseFloat(e.target.value); post('preview', { model: sel.buy, tack: {}, scale: buyForm.scale }); $('scale-label').textContent = `${t('ui.size')} · ${buyForm.scale.toFixed(2)}`; };
    const buyGo = $('buy-go'); if (buyGo) buyGo.onclick = async () => { const r = await post('buy', { model: sel.buy, name: buyForm.name, gender: buyForm.gender, scale: buyForm.scale }); if (r.ok) { D = r.data; setTab('owned'); toast(t('ui.done')); } else if (r.error) toast(t('error.' + r.error), true); };
    document.querySelectorAll('[data-t]').forEach(b => b.onclick = async () => {
      const a = b.dataset.t; const p = D.tack.find(x => x.id === sel.tack); let r;
      if (a === 'buy' || a === 'sell') r = await post('tack', { action: a, piece: p.id });
      else if (a === 'equip') r = await post('action', { action: 'equip', id: sel.owned, arg: { slot: p.slot, piece: p.id } });
      else if (a === 'unequip') r = await post('action', { action: 'equip', id: sel.owned, arg: { slot: p.slot, piece: false } });
      if (r && r.ok) { D = r.data; render(); toast(t('ui.done')); } else if (r && r.error) toast(t('error.' + r.error), true);
    });
    const mg = $('market-go'); if (mg) mg.onclick = async () => { const r = await post('marketBuy', { id: sel.market }); if (r.ok) { D = r.data; setTab('owned'); toast(t('ui.done')); } else if (r.error) toast(t('error.' + r.error), true); };
    const wc = $('wild-claim'); if (wc) wc.onclick = async () => { const r = await post('wild', { sell: false }); if (r.ok) { D = r.data; setTab('owned'); } else if (r.error) toast(t('error.' + r.error), true); };
    const ws = $('wild-sell'); if (ws) ws.onclick = async () => { const r = await post('wild', { sell: true }); if (r.ok) { D = r.data; render(); } else if (r.error) toast(t('error.' + r.error), true); };
  }

  document.querySelectorAll('.st-tabs .lxr-chip').forEach(b => b.onclick = () => setTab(b.dataset.tab));
  ['buy-class', 'buy-breed', 'tack-slot', 'tack-owned-only'].forEach(id => $(id).onchange = render);
  document.addEventListener('keydown', e => { if (e.key === 'Escape' || (e.key === 'Backspace' && !(document.activeElement && document.activeElement.tagName === 'INPUT'))) post('close'); });

  window.addEventListener('message', e => {
    const m = e.data || {};
    if (m.action === 'open') { D = m.data; L = D.locale || {}; sel = { owned: D.owned[0] ? D.owned[0].id : null, buy: null, tack: null, market: null }; applyLocale(); app.classList.remove('lxr-hidden'); setTab('owned'); }
    else if (m.action === 'close') { app.classList.add('lxr-hidden'); D = null; }
  });
})();
