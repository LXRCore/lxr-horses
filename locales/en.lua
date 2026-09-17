--[[ ═══════════════════════════════════════════════════════════════════════════
     LXR-HORSES — Locale: English (canonical)
     Developer   : iBoss21 | Brand : LXRCore | https://www.lxrcore.com
     © 2026 iBoss21 / LXRCore — All Rights Reserved
     ═══════════════════════════════════════════════════════════════════════════ ]]

Locale.Register('en', {
    prompt = {
        stable = '%{name}', feed = 'Feed', brush = 'Brush', pat = 'Pat', lead = 'Lead', saddlebags = 'Saddlebags', inspect = 'Inspect',
        train = 'Training: %{course}', accept_horse = 'Accept %{name}', decline_horse = 'Decline',
    },
    ui = {
        horse = 'Horse', transfer = 'Horse transfer', saddlebags = '%{name} — Saddlebags',
        tab_owned = 'My horses', tab_buy = 'Buy', tab_tack = 'Tack', tab_market = 'Market', tab_breed = 'Breeding',
        owned_only = 'Owned only', hint_close = 'Backspace — close', no_horses = 'You own no horses yet.', out = 'Out', listed = 'Listed',
        bond = 'Bond', all_classes = 'All classes', all_breeds = 'All breeds', tier = 'Tier', no_listings = 'Nobody is selling right now.',
        breeding_off = 'Breeding is not offered here.', sire = 'Stallion', dam = 'Mare',
        breed_note = 'Stud fee $%{fee}. The foal is ready after %{hours} hours. Both parents need bond %{bond}.',
        breed = 'Breed', collect_foals = 'Collect foals', bred = 'The mare is in foal.', foal_collected = 'A foal has been registered in your name.',
        pick_horse = 'Pick a horse from the list.', pick_stock = 'Pick a horse to see its papers.', pick_tack = 'Pick a piece of tack.', pick_listing = 'Pick a listing.',
        age = 'Age (days)', injured = 'Injured', dead = 'Dead', shoes = 'Shoes', insured = 'Insured', uninsured = 'Uninsured',
        take_out = 'Take out', store = 'Stable', favorite = 'Favourite', unfavorite = 'Unfavourite', rename = 'Rename', insure = 'Insure', vet = 'Veterinary',
        unlist = 'Withdraw listing', list_market = 'List on market', sell = 'Sell', equip_hint = 'Tack is fitted from the Tack tab.',
        gender = 'Sex', name = 'Name', size = 'Size', buy = 'Buy', owned_count = '%{n} / %{max} owned',
        cosmetic = 'Cosmetic', tack_owned = 'You own %{n} (%{free} not fitted)', equip_on = 'Fit on %{name}', unequip = 'Remove from horse', equip_pick = 'Select the horse under My horses first.',
        seller = 'Seller', pending_wild = 'Wild catch waiting: %{label}', wild_pending = 'A wild horse you tamed is outside. Register it or sell it to the stable.',
        claim = 'Register', done = 'Done', rename_prompt = 'New name:', list_prompt = 'Asking price ($%{min} – $%{max}):', sell_confirm = 'Sell this horse to the stable?',
    },
    gender = { male = 'Stallion', female = 'Mare', gelding = 'Gelding' },
    class = { draft = 'Draft', work = 'Work', riding = 'Riding', race = 'Race', war = 'War', multi = 'Multi-class', pack = 'Pack' },
    rarity = { common = 'Common', uncommon = 'Uncommon', rare = 'Rare', exquisite = 'Exquisite', legendary = 'Legendary' },
    temper = { docile = 'Docile', steady = 'Steady', spirited = 'Spirited', nervous = 'Nervous', fierce = 'Fierce' },
    stat = { speed = 'Speed', acceleration = 'Acceleration', health = 'Health', stamina = 'Stamina', handling = 'Handling', courage = 'Courage', storage = 'Storage' },
    core = { health = 'Health', stamina = 'Stamina', hunger = 'Hunger', thirst = 'Thirst', cleanliness = 'Clean', mood = 'Mood' },
    personality = 'Temperament',
    tag = { bond = 'Bond %{level}' },
    info = {
        bought = '%{name} is yours.', sold = 'Sold to the stable.', bond_up = '%{name} trusts you more (bond %{level}).',
        horse_ignores = '%{name} ignores you.', inspect = '%{name} — %{breed}. Speed %{speed}, stamina %{stamina}, health %{health}. Bond %{bond}, %{personality}.',
        transfer_sent = 'Offer sent.', transfer_offer = '%{name} is being offered to you by player %{id}.', transfer_declined = 'They declined.',
        transfer_done = '%{name} now belongs to them.', transfer_received = '%{name} is yours now.',
        tamed = 'You calmed the %{label}. Ride it to a stable to register it.', training_started = '%{course}: ride every marker within %{time} s.',
        training_done = 'Training complete: +%{xp} bond, %{stat} improved.', training_failed = 'Training failed.',
        core_low = "%{name}'s %{core} is low.", neglect_injured = '%{name} has fallen ill from neglect.', old_age = '%{name} has died of old age.',
        horse_dead = '%{name} is dead.', horse_dead_insured = '%{name} was killed; the insurance brings it back to the stable, injured.',
        horse_dead_stable = '%{name} was badly hurt and taken to the stable.', market_sold = '%{name} sold on the market for $%{amount}.',
        foal_born = '%{count} foal(s) registered.', given = 'Gave a %{label}.',
    },
    error = {
        rate = 'Slow down', no_player = 'Not loaded', busy = 'Not now', cooldown = 'Wait a moment', restricted = 'You cannot call a horse here',
        no_horse = 'You have no horse to call', injured = 'That horse is injured', listed = 'That horse is listed for sale', spawn_failed = 'The horse could not come',
        too_far = 'Too far away', invalid = 'That is not possible', invalid_item = 'A horse cannot use that', not_injured = 'The horse is not injured',
        no_item = 'You do not have that', not_owner = 'Not your horse', no_feed = 'You have nothing to feed it', no_inventory = 'Inventory unavailable',
        limit = 'You own too many horses', bad_name = 'That name is not allowed', no_money = 'You cannot afford that', favorites = 'Too many favourites',
        uninsured = 'The horse was not insured', not_owned_tack = 'You do not own that tack', bad_price = 'Bad price', listings = 'Too many listings',
        own_listing = 'That is your own listing', expired = 'Listing expired', target_limit = 'They own too many horses', skill_low = 'Your horsemanship is too low (needs %{level})',
        no_wild = 'No wild horse to register', bring_horse = 'Bring the horse to the stable', claim_cooldown = 'You registered a wild horse recently', claim_limit = 'No more registrations today',
        bad_pair = 'You need a stallion and a mare', bond_low = 'Both horses need a stronger bond', mare_cooldown = 'The mare needs rest', nothing_due = 'No foal is due yet',
        mount_first = 'Mount your horse first', closed = 'Closed',
    },
    command = { givehorse = 'Give a horse to a player (admin)' },
})
