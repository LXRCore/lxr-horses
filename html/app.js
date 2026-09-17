/* 🐺 LXR-HORSES — Stable UI | © 2026 iBoss21 / LXRCore */
(function () {
  const $ = (id) => document.getElementById(id);
  const app = $('app');
  const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'lxr-horses';
  let D = null;          // payload from the server
  let L = {};            // locale bundle
  let tab = 'owned';
  let sel = { owned: null, buy: null, tack: null, market: null };
  let buyForm = { name: '', gender: 'gelding', scale: 1.0 };
  let breedSel = { sire: null, dam: null };

  const t = (k, vars) => { let s = L[k] || k; if (vars) for (const v in vars) s = s.replace('%{' + v + '}', vars[v]); return s; };
  const money = (n) => (Math.round((n || 0) * 100) / 100).toFixed(2);
  const post = (name, body) => fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) }).then(r => r.json()).catch(() => ({ ok: false }));
  const STATS = ['speed', 'acceleration', 'health', 'stamina', 'handling', 'courage'];
  const CORES = ['health', 'stamina', 'hunger', 'thirst', 'cleanliness', 'mood'];

  let toastEl;
  function toast(msg, err) {
    if (!toastEl) { toastEl = document.createElement('div'); toastEl.className = 'toast'; document.body.appendChild(toastEl); }
    toastEl.textContent = msg; toastEl.classList.toggle('err', !!err); toastEl.classList.add('show');
    setTimeout(() => toastEl.classList.remove('show'), 2500);
  }

  function applyLocale() { document.querySelectorAll('[data-l]').forEach(el => { el.textContent = t('ui.' + el.dataset.l); }); }

  function setTab(name) {
    tab = name;
    document.querySelectorAll('.tabs button').forEach(b => b.classList.toggle('active', b.dataset.tab === name));
    document.querySelectorAll('.tab').forEach(s => s.classList.toggle('active', s.id === 'tab-' + name));
    render();
  }

  // ─── lists ───
  function ownedList() {
    const box = $('owned-list'); box.innerHTML = '';
    if (!D.owned.length) { box.innerHTML = `<div class="note">${t('ui.no_horses')}</div>`; return; }
    D.owned.forEach(h => {
      const c = document.createElement('div');
      c.className = 'card' + (h.favorite ? ' fav' : '') + (h.injured ? ' injured' : '') + (h.dead ? ' dead' : '') + (sel.owned === h.id ? ' sel' : '');
      c.innerHTML = `<div class="t">${esc(h.name)} ${h.active ? `<span class="badge">${t('ui.out')}</span>` : ''}${h.listing ? `<span class="badge">${t('ui.listed')}</span>` : ''}</div>
        <div class="p">${t('ui.bond')} ${h.bond}</div><div class="s">${esc(h.breed)} · ${esc(h.coat)} · ${t('gender.' + h.gender)}</div>`;
      c.onclick = () => { sel.owned = h.id; post('preview', { model: h.model, tack: h.tack, scale: h.scale }); render(); };
      box.appendChild(c);
    });
  }

  function buyList() {
    const cls = $('buy-class'), br = $('buy-breed');
    const classes = [...new Set(D.stock.map(s => s.class))].sort();
    const breeds = [...new Set(D.stock.filter(s => !cls.value || s.class === cls.value).map(s => s.breed))].sort();
    if (cls.options.length !== classes.length + 1) { cls.innerHTML = `<option value="">${t('ui.all_classes')}</option>` + classes.map(c => `<option value="${c}">${t('class.' + c)}</option>`).join(''); }
    const prevBreed = br.value;
    br.innerHTML = `<option value="">${t('ui.all_breeds')}</option>` + breeds.map(b => `<option value="${esc(b)}">${esc(b)}</option>`).join('');
    if (breeds.includes(prevBreed)) br.value = prevBreed;
    const box = $('buy-list'); box.innerHTML = '';
    D.stock.filter(s => (!cls.value || s.class === cls.value) && (!br.value || s.breed === br.value)).forEach(s => {
      const c = document.createElement('div');
      c.className = 'card' + (sel.buy === s.model ? ' sel' : '');
      c.innerHTML = `<div class="t">${esc(s.breed)} — ${esc(s.coat)}</div><div class="p">$${money(s.price)}</div><div class="s">${t('class.' + s.class)} · ${t('rarity.' + s.rarity)} · ${t('temper.' + s.temperament)}</div>`;
      c.onclick = () => { sel.buy = s.model; buyForm.name = s.coat; post('preview', { model: s.model, tack: {}, scale: buyForm.scale }); render(); };
      box.appendChild(c);
    });
  }

  function tackList() {
    const slotSel = $('tack-slot');
    const slots = Object.keys(D.options.slots).sort((a, b) => D.options.slots[a].order - D.options.slots[b].order);
    if (slotSel.options.length !== slots.length) slotSel.innerHTML = slots.map(s => `<option value="${s}">${esc(D.options.slots[s].label)}</option>`).join('');
    const ownedOnly = $('tack-owned-only').checked;
    const ownedCount = {}; D.ownedTack.forEach(r => { ownedCount[r.piece] = (ownedCount[r.piece] || 0) + 1; });
    const box = $('tack-list'); box.innerHTML = '';
    D.tack.filter(p => p.slot === slotSel.value && (!ownedOnly || ownedCount[p.id])).forEach(p => {
      const c = document.createElement('div');
      c.className = 'card' + (sel.tack === p.id ? ' sel' : '');
      const st = Object.entries(p.stats || {}).map(([k, v]) => `${t('stat.' + k)} +${v}`).join(' · ');
      c.innerHTML = `<div class="t">${esc(p.label)} ${ownedCount[p.id] ? `<span class="badge">×${ownedCount[p.id]}</span>` : ''}</div><div class="p">$${money(p.price)}</div><div class="s">${t('ui.tier')} ${p.tier}${st ? ' · ' + st : ''}</div>`;
      c.onclick = () => {
        sel.tack = p.id;
        const h = D.owned.find(x => x.id === sel.owned) || D.owned[0];
        if (h) { const tk = Object.assign({}, h.tack); tk[p.slot] = p.id; post('preview', { model: h.model, tack: tk, scale: h.scale }); }
        render();
      };
      box.appendChild(c);
    });
  }

  function marketList() {
    const box = $('market-list'); box.innerHTML = '';
    if (!D.market.length) { box.innerHTML = `<div class="note">${t('ui.no_listings')}</div>`; return; }
    D.market.forEach(h => {
      const c = document.createElement('div');
      c.className = 'card' + (sel.market === h.id ? ' sel' : '');
      c.innerHTML = `<div class="t">${esc(h.name)}</div><div class="p">$${money(h.price)}</div><div class="s">${esc(h.breed)} · ${esc(h.coat)} · ${t('ui.bond')} ${h.bond} · ${esc(h.seller)}</div>`;
      c.onclick = () => { sel.market = h.id; post('preview', { model: h.model, tack: h.tack, scale: h.scale }); render(); };
      box.appendChild(c);
    });
  }

  function breedBox() {
    const box = $('breed-box');
    if (!D.options.breeding) { box.innerHTML = `<div class="note">${t('ui.breeding_off')}</div>`; return; }
    const sires = D.owned.filter(h => h.gender === 'male' && !h.dead), dams = D.owned.filter(h => h.gender === 'female' && !h.dead);
    const opt = (list, cur) => `<option value="">—</option>` + list.map(h => `<option value="${h.id}" ${cur === h.id ? 'selected' : ''}>${esc(h.name)} (${t('ui.bond')} ${h.bond})</option>`).join('');
    const due = (D.breeding || []).length;
    box.innerHTML = `<div class="field"><span>${t('ui.sire')}</span><select id="breed-sire">${opt(sires, breedSel.sire)}</select></div>
      <div class="field"><span>${t('ui.dam')}</span><select id="breed-dam">${opt(dams, breedSel.dam)}</select></div>
      <div class="note">${t('ui.breed_note', { fee: money(D.options.breeding.fee), hours: D.options.breeding.gestationHours, bond: D.options.breeding.minBond })}</div>
      <div class="row"><button class="btn" id="breed-go">${t('ui.breed')} — $${money(D.options.breeding.fee)}</button>
      <button class="btn ghost" id="breed-collect" ${due ? '' : 'disabled'}>${t('ui.collect_foals')} (${due})</button></div>`;
    $('breed-sire').onchange = e => breedSel.sire = +e.target.value || null;
    $('breed-dam').onchange = e => breedSel.dam = +e.target.value || null;
    $('breed-go').onclick = async () => { if (!breedSel.sire || !breedSel.dam) return toast(t('error.bad_pair'), true); const r = await post('breed', { sire: breedSel.sire, dam: breedSel.dam }); if (r.ok) { D = r.data; toast(t('ui.bred')); render(); } };
    $('breed-collect').onclick = async () => { const r = await post('breed', { collect: true }); if (r.ok) { D = r.data; toast(t('ui.foal_collected')); render(); } };
  }

  // ─── detail ───
  function bars(stats, cls) {
    return STATS.map(k => `<span>${t('stat.' + k)}</span><div class="bar ${cls || ''}"><i style="width:${Math.round((stats[k] || 0) * 10)}%"></i></div><span>${(Math.round((stats[k] || 0) * 10) / 10)}</span>`).join('');
  }
  function coreBars(cores) {
    return CORES.map(k => `<span>${t('core.' + k)}</span><div class="bar core ${(cores[k] || 0) < 25 ? 'low' : ''}"><i style="width:${Math.round(cores[k] || 0)}%"></i></div><span>${Math.round(cores[k] || 0)}</span>`).join('');
  }

  function detailOwned() {
    const h = D.owned.find(x => x.id === sel.owned);
    if (!h) return `<div class="dcard"><div class="sub">${t('ui.pick_horse')}</div></div>`;
    const tackRows = Object.keys(D.options.slots).sort((a, b) => D.options.slots[a].order - D.options.slots[b].order).map(s => {
      const pid = h.tack[s]; const piece = pid ? D.tack.find(p => p.id === pid) : null;
      return `<div><span>${esc(D.options.slots[s].label)}</span><b>${piece ? esc(piece.label) : (pid ? pid : '—')}</b></div>`;
    }).join('');
    const insured = h.insuredUntil && h.insuredUntil * 1000 > Date.now();
    return `<div class="dcard">
      <h2>${esc(h.name)} ${h.favorite ? '★' : ''}</h2>
      <div class="sub">${esc(h.breed)} · ${esc(h.coat)} · ${t('gender.' + h.gender)} · ${t('personality')}: ${esc(h.personalityLabel || '')} · ${t('ui.age')} ${h.ageDays}${h.injured ? ' · <b style="color:var(--danger)">' + t('ui.injured') + '</b>' : ''}${h.dead ? ' · <b style="color:var(--danger)">' + t('ui.dead') + '</b>' : ''}</div>
      <div class="stats">${bars(h.stats)}</div>
      <div class="stats">${coreBars(h.cores)}</div>
      <div class="note">${t('ui.bond')} ${h.bond} · ${Math.round(h.bondProgress * 100)}% · ${t('ui.shoes')} ${Math.round(h.shoesLeft)}h · ${insured ? t('ui.insured') : t('ui.uninsured')}</div>
      <div class="tackslots">${tackRows}</div>
      <div class="row">
        <button class="btn" data-a="select" ${h.dead || h.injured || h.listing ? 'disabled' : ''}>${t('ui.take_out')}</button>
        <button class="btn ghost" data-a="store" ${!h.active ? 'disabled' : ''}>${t('ui.store')}</button>
        <button class="btn ghost" data-a="favorite">${h.favorite ? t('ui.unfavorite') : t('ui.favorite')}</button>
        <button class="btn ghost" data-a="rename">${t('ui.rename')} ($${money(D.options.renamePrice)})</button>
        <button class="btn ghost" data-a="insure" ${!D.options.insurance.enabled ? 'disabled' : ''}>${t('ui.insure')} ($${money(h.insurancePrice)})</button>
        <button class="btn ghost" data-a="vet" ${!(h.injured || h.dead) ? 'disabled' : ''}>${t('ui.vet')} ($${money(h.dead ? D.options.insurance.revivePrice : D.options.vetPrice)})</button>
        ${h.listing ? `<button class="btn ghost" data-a="unlist">${t('ui.unlist')}</button>` : `<button class="btn ghost" data-a="list">${t('ui.list_market')}</button>`}
        <button class="btn danger" data-a="sell" ${h.active || h.listing ? 'disabled' : ''}>${t('ui.sell')} ($${money(h.sellValue)})</button>
      </div>
      <div class="field" id="equip-box"><span>${t('ui.equip_hint')}</span></div>
    </div>`;
  }

  function detailBuy() {
    const s = D.stock.find(x => x.model === sel.buy);
    if (!s) return `<div class="dcard"><div class="sub">${t('ui.pick_stock')}</div></div>`;
    const st = {}; STATS.forEach((k, i) => st[k] = s.stats[k]);
    const g = D.options.genderChoice ? `<div class="field"><span>${t('ui.gender')}</span><div class="gender">${['male', 'female', 'gelding'].map(x => `<button class="btn ghost ${buyForm.gender === x ? 'on' : ''}" data-g="${x}">${t('gender.' + x)}</button>`).join('')}</div></div>` : '';
    const [lo, hi] = D.options.scaleRange;
    return `<div class="dcard">
      <h2>${esc(s.breed)} — ${esc(s.coat)}</h2>
      <div class="sub">${t('class.' + s.class)} · ${t('rarity.' + s.rarity)} · ${t('temper.' + s.temperament)} · ${t('ui.tier')} ${s.tier}</div>
      <div class="desc">${esc(s.description || '')}</div>
      <div class="stats">${bars(st)}</div>
      <div class="field"><span>${t('ui.name')}</span><input type="text" id="buy-name" maxlength="24" value="${esc(buyForm.name)}"></div>
      ${g}
      <div class="field"><span>${t('ui.size')} (${buyForm.scale.toFixed(2)})</span><input type="range" id="buy-scale" min="${lo}" max="${hi}" step="0.01" value="${buyForm.scale}"></div>
      <div class="row"><button class="btn" id="buy-go" ${D.count >= D.limit ? 'disabled' : ''}>${t('ui.buy')} — $${money(s.price)}</button><span class="note">${t('ui.owned_count', { n: D.count, max: D.limit })}</span></div>
    </div>`;
  }

  function detailTack() {
    const p = D.tack.find(x => x.id === sel.tack);
    if (!p) return `<div class="dcard"><div class="sub">${t('ui.pick_tack')}</div></div>`;
    const owned = D.ownedTack.filter(r => r.piece === p.id);
    const free = owned.filter(r => !r.horse_id).length;
    const h = D.owned.find(x => x.id === sel.owned);
    const st = Object.entries(p.stats || {}).map(([k, v]) => `${t('stat.' + k)} +${v}`).join(' · ') || t('ui.cosmetic');
    return `<div class="dcard">
      <h2>${esc(p.label)}</h2>
      <div class="sub">${esc(D.options.slots[p.slot].label)} · ${t('ui.tier')} ${p.tier} · ${st}</div>
      <div class="note">${t('ui.tack_owned', { n: owned.length, free })}</div>
      <div class="row">
        <button class="btn" data-t="buy">${t('ui.buy')} — $${money(p.price)}</button>
        <button class="btn ghost" data-t="sell" ${free ? '' : 'disabled'}>${t('ui.sell')} — $${money(p.price * 0.5)}</button>
        <button class="btn ghost" data-t="equip" ${(h && free) ? '' : 'disabled'}>${t('ui.equip_on', { name: h ? esc(h.name) : '…' })}</button>
        <button class="btn ghost" data-t="unequip" ${(h && h.tack[p.slot]) ? '' : 'disabled'}>${t('ui.unequip')}</button>
      </div>
      <div class="note">${t('ui.equip_pick')}</div>
    </div>`;
  }

  function detailMarket() {
    const h = D.market.find(x => x.id === sel.market);
    if (!h) return `<div class="dcard"><div class="sub">${t('ui.pick_listing')}</div></div>`;
    return `<div class="dcard"><h2>${esc(h.name)}</h2><div class="sub">${esc(h.breed)} · ${esc(h.coat)} · ${t('gender.' + h.gender)} · ${esc(h.personalityLabel || '')} · ${t('ui.seller')}: ${esc(h.seller)}</div>
      <div class="stats">${bars(h.stats)}</div><div class="stats">${coreBars(h.cores)}</div>
      <div class="row"><button class="btn" id="market-go" ${D.count >= D.limit ? 'disabled' : ''}>${t('ui.buy')} — $${money(h.price)}</button></div></div>`;
  }

  function render() {
    if (!D) return;
    $('stable-name').textContent = D.stable.label;
    $('cash').textContent = money(D.cash);
    $('pending-wild').textContent = D.pendingWild ? t('ui.pending_wild', { label: D.pendingWild.label }) : '';
    ownedList(); buyList(); tackList(); marketList(); breedBox();
    const det = $('detail');
    det.innerHTML = tab === 'owned' ? detailOwned() : tab === 'buy' ? detailBuy() : tab === 'tack' ? detailTack() : tab === 'market' ? detailMarket() : (D.pendingWild ? wildBox() : '');
    bind();
  }

  function wildBox() {
    const w = D.pendingWild;
    return `<div class="dcard"><h2>${esc(w.label)}</h2><div class="sub">${t('ui.wild_pending')}</div>
      <div class="row"><button class="btn" id="wild-claim">${t('ui.claim')} — $${money(w.fee)}</button><button class="btn ghost" id="wild-sell">${t('ui.sell')} — $${money(w.sell)}</button></div></div>`;
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
    const scaleEl = $('buy-scale'); if (scaleEl) scaleEl.oninput = e => { buyForm.scale = parseFloat(e.target.value); post('preview', { model: sel.buy, tack: {}, scale: buyForm.scale }); e.target.previousElementSibling.textContent = `${t('ui.size')} (${buyForm.scale.toFixed(2)})`; };
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

  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }

  document.querySelectorAll('.tabs button').forEach(b => b.onclick = () => setTab(b.dataset.tab));
  ['buy-class', 'buy-breed', 'tack-slot', 'tack-owned-only'].forEach(id => $(id).onchange = render);
  document.addEventListener('keydown', e => { if (e.key === 'Escape' || e.key === 'Backspace') { if (document.activeElement && document.activeElement.tagName === 'INPUT') return; post('close'); } });

  window.addEventListener('message', e => {
    const m = e.data || {};
    if (m.action === 'open') {
      D = m.data; L = D.locale || {};
      sel = { owned: D.owned[0] ? D.owned[0].id : null, buy: null, tack: null, market: null };
      applyLocale(); app.classList.remove('hidden'); setTab('owned');
    } else if (m.action === 'close') { app.classList.add('hidden'); D = null; }
  });
})();
