--[[ ═══════════════════════════════════════════════════════════════════════════
     LXR-HORSES — Locale: Georgian (ქართული) — 1:1 mirror of en.lua
     Developer   : iBoss21 | Brand : LXRCore | https://www.lxrcore.com
     © 2026 iBoss21 / LXRCore — All Rights Reserved
     ═══════════════════════════════════════════════════════════════════════════ ]]

Locale.Register('ka', {
    prompt = {
        stable = '%{name}', feed = 'კვება', brush = 'გაწმენდა', pat = 'მოფერება', lead = 'წაყვანა', saddlebags = 'უნაგირის ჩანთები', inspect = 'დათვალიერება',
        train = 'წვრთნა: %{course}', accept_horse = 'მიიღეთ %{name}', decline_horse = 'უარყოფა',
    },
    ui = {
        horse = 'ცხენი', transfer = 'ცხენის გადაცემა', saddlebags = '%{name} — უნაგირის ჩანთები',
        tab_owned = 'ჩემი ცხენები', tab_buy = 'ყიდვა', tab_tack = 'აღკაზმულობა', tab_market = 'ბაზარი', tab_breed = 'გამრავლება',
        owned_only = 'მხოლოდ ჩემი', hint_close = 'Backspace — დახურვა', no_horses = 'ჯერ ცხენი არ გყავთ.', out = 'გარეთ', listed = 'გასაყიდია',
        bond = 'ნდობა', all_classes = 'ყველა კლასი', all_breeds = 'ყველა ჯიში', tier = 'დონე', no_listings = 'ახლა არავინ ყიდის.',
        breeding_off = 'გამრავლება აქ არ არის შესაძლებელი.', sire = 'ულაყი', dam = 'ფაშატი',
        breed_note = 'გადასახადი $%{fee}. კვიცი მზად იქნება %{hours} საათში. ორივე მშობელს სჭირდება ნდობა %{bond}.',
        breed = 'გამრავლება', collect_foals = 'კვიცების აყვანა', bred = 'ფაშატი მაკეა.', foal_collected = 'კვიცი თქვენს სახელზე დარეგისტრირდა.',
        pick_horse = 'აირჩიეთ ცხენი სიიდან.', pick_stock = 'აირჩიეთ ცხენი დოკუმენტების სანახავად.', pick_tack = 'აირჩიეთ აღკაზმულობა.', pick_listing = 'აირჩიეთ განცხადება.',
        age = 'ასაკი (დღე)', injured = 'დაშავებული', dead = 'მკვდარი', shoes = 'ნალები', insured = 'დაზღვეული', uninsured = 'დაუზღვეველი',
        take_out = 'გამოყვანა', store = 'თავლაში', favorite = 'რჩეული', unfavorite = 'რჩეულიდან მოხსნა', rename = 'სახელის შეცვლა', insure = 'დაზღვევა', vet = 'ვეტერინარი',
        unlist = 'განცხადების მოხსნა', list_market = 'ბაზარზე გატანა', sell = 'გაყიდვა', equip_hint = 'აღკაზმულობა „აღკაზმულობის“ ჩანართიდან ეყრება.',
        gender = 'სქესი', name = 'სახელი', size = 'ზომა', buy = 'ყიდვა', owned_count = '%{n} / %{max} გყავთ',
        cosmetic = 'დეკორატიული', tack_owned = 'გაქვთ %{n} (%{free} აუყრელი)', equip_on = 'აყრა: %{name}', unequip = 'ცხენიდან მოხსნა', equip_pick = 'ჯერ აირჩიეთ ცხენი „ჩემი ცხენები“-ში.',
        seller = 'გამყიდველი', pending_wild = 'გარეული ცხენი ელოდება: %{label}', wild_pending = 'თქვენ მიერ დამორჩილებული გარეული ცხენი გარეთაა. დაარეგისტრირეთ ან მიყიდეთ თავლას.',
        claim = 'რეგისტრაცია', done = 'შესრულდა', rename_prompt = 'ახალი სახელი:', list_prompt = 'ფასი ($%{min} – $%{max}):', sell_confirm = 'მიყიდოთ ეს ცხენი თავლას?',
    },
    gender = { male = 'ულაყი', female = 'ფაშატი', gelding = 'დაკოდილი' },
    class = { draft = 'გამწევი', work = 'სამუშაო', riding = 'საჯდომი', race = 'სარბოლო', war = 'საბრძოლო', multi = 'უნივერსალური', pack = 'სატვირთო' },
    rarity = { common = 'ჩვეულებრივი', uncommon = 'იშვიათი', rare = 'ძალიან იშვიათი', exquisite = 'განსაკუთრებული', legendary = 'ლეგენდარული' },
    temper = { docile = 'მშვიდი', steady = 'მყარი', spirited = 'ცოცხალი', nervous = 'ნერვიული', fierce = 'მძვინვარე' },
    stat = { speed = 'სიჩქარე', acceleration = 'აჩქარება', health = 'ჯანმრთელობა', stamina = 'გამძლეობა', handling = 'მართვა', courage = 'სიმამაცე', storage = 'ტევადობა' },
    core = { health = 'ჯანმრთელობა', stamina = 'გამძლეობა', hunger = 'შიმშილი', thirst = 'წყურვილი', cleanliness = 'სისუფთავე', mood = 'განწყობა' },
    personality = 'ხასიათი',
    tag = { bond = 'ნდობა %{level}' },
    info = {
        bought = '%{name} თქვენია.', sold = 'თავლას მიეყიდა.', bond_up = '%{name} უფრო გენდობათ (ნდობა %{level}).',
        horse_ignores = '%{name} არ გისმენთ.', inspect = '%{name} — %{breed}. სიჩქარე %{speed}, გამძლეობა %{stamina}, ჯანმრთელობა %{health}. ნდობა %{bond}, %{personality}.',
        transfer_sent = 'შეთავაზება გაიგზავნა.', transfer_offer = 'მოთამაშე %{id} გთავაზობთ ცხენს %{name}.', transfer_declined = 'უარი თქვეს.',
        transfer_done = '%{name} ახლა მათია.', transfer_received = '%{name} ახლა თქვენია.',
        tamed = 'დაამშვიდეთ %{label}. წაიყვანეთ თავლაში დასარეგისტრირებლად.', training_started = '%{course}: გაიარეთ ყველა ნიშანი %{time} წამში.',
        training_done = 'წვრთნა დასრულდა: +%{xp} ნდობა, %{stat} გაუმჯობესდა.', training_failed = 'წვრთნა ჩაიშალა.',
        core_low = '%{name}-ს %{core} დაბალია.', neglect_injured = '%{name} უყურადღებობისგან დაავადდა.', old_age = '%{name} სიბერით მოკვდა.',
        horse_dead = '%{name} მკვდარია.', horse_dead_insured = '%{name} მოკლეს; დაზღვევა თავლაში აბრუნებს დაშავებულს.',
        horse_dead_stable = '%{name} მძიმედ დაშავდა და თავლაში წაიყვანეს.', market_sold = '%{name} ბაზარზე გაიყიდა $%{amount}-ად.',
        foal_born = '%{count} კვიცი დარეგისტრირდა.', given = 'გადაეცა %{label}.',
    },
    error = {
        rate = 'შეანელეთ', no_player = 'არ არის ჩატვირთული', busy = 'ახლა არა', cooldown = 'ცოტა მოიცადეთ', restricted = 'აქ ცხენის გამოძახება არ შეიძლება',
        no_horse = 'გამოსაძახებელი ცხენი არ გყავთ', injured = 'ეს ცხენი დაშავებულია', listed = 'ეს ცხენი გასაყიდადაა გამოტანილი', spawn_failed = 'ცხენმა ვერ მოაღწია',
        too_far = 'ძალიან შორს ხართ', invalid = 'ეს შეუძლებელია', invalid_item = 'ცხენს ეს არ გამოადგება', not_injured = 'ცხენი არ არის დაშავებული',
        no_item = 'ეს არ გაქვთ', not_owner = 'ეს თქვენი ცხენი არ არის', no_feed = 'საკვები არ გაქვთ', no_inventory = 'ინვენტარი მიუწვდომელია',
        limit = 'ძალიან ბევრი ცხენი გყავთ', bad_name = 'ეს სახელი დაუშვებელია', no_money = 'საკმარისი ფული არ გაქვთ', favorites = 'ძალიან ბევრი რჩეული',
        uninsured = 'ცხენი დაზღვეული არ იყო', not_owned_tack = 'ეს აღკაზმულობა თქვენი არ არის', bad_price = 'არასწორი ფასი', listings = 'ძალიან ბევრი განცხადება',
        own_listing = 'ეს თქვენი განცხადებაა', expired = 'განცხადებას ვადა გაუვიდა', target_limit = 'მათ ძალიან ბევრი ცხენი ჰყავთ', skill_low = 'თქვენი მხედრობა დაბალია (საჭიროა %{level})',
        no_wild = 'დასარეგისტრირებელი გარეული ცხენი არ არის', bring_horse = 'მიიყვანეთ ცხენი თავლაში', claim_cooldown = 'ახლახან დაარეგისტრირეთ გარეული ცხენი', claim_limit = 'დღეს მეტი რეგისტრაცია არ შეიძლება',
        bad_pair = 'გჭირდებათ ულაყი და ფაშატი', bond_low = 'ორივე ცხენს უფრო ძლიერი ნდობა სჭირდება', mare_cooldown = 'ფაშატს დასვენება სჭირდება', nothing_due = 'კვიცი ჯერ არ არის მზად',
        mount_first = 'ჯერ შეჯექით ცხენზე', closed = 'დახურულია',
    },
    command = { givehorse = 'ცხენის გადაცემა მოთამაშისთვის (ადმინი)' },
})
