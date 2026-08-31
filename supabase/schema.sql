-- KIDS-ART: locations table, RLS policies, storage bucket, and seed data.
-- Run this once in Supabase Dashboard -> SQL Editor -> New query -> Run.
-- Safe to re-run: every statement is idempotent (IF NOT EXISTS / ON CONFLICT DO NOTHING).

create extension if not exists pgcrypto;

create table if not exists public.locations (
  id text primary key default gen_random_uuid()::text,
  name_ru text not null,
  name_uk text not null,
  district text not null,
  district_name_ru text not null,
  district_name_uk text not null,
  type text not null check (type in ('free', 'mall', 'nature', 'other')),
  format_ru text,
  format_uk text,
  is_paid boolean not null default true,
  payment_note_ru text,
  payment_note_uk text,
  desc_ru text,
  desc_uk text,
  img text,
  map_query text,
  lat double precision,
  lng double precision,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  telegram_message_id bigint,
  created_at timestamptz not null default now()
);

-- No matter what a public client sends, a freshly-submitted row always starts
-- as 'pending'. Only the service_role key (used exclusively by the Edge
-- Functions) is allowed to move a row to 'approved' / 'rejected'.
create or replace function public.force_pending_status()
returns trigger
language plpgsql
as $$
begin
  if new.status is distinct from 'pending'
     and coalesce(current_setting('request.jwt.claim.role', true), '') is distinct from 'service_role' then
    new.status := 'pending';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_force_pending_status on public.locations;
create trigger trg_force_pending_status
  before insert on public.locations
  for each row execute function public.force_pending_status();

alter table public.locations enable row level security;

drop policy if exists "public can read approved locations" on public.locations;
create policy "public can read approved locations"
  on public.locations for select
  using (status = 'approved');

drop policy if exists "public can suggest a location" on public.locations;
create policy "public can suggest a location"
  on public.locations for insert
  with check (true); -- the trigger above sanitizes status regardless of input

-- Storage bucket for photos attached to "suggest a location" submissions.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('location-photos', 'location-photos', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

drop policy if exists "anyone can view location photos" on storage.objects;
create policy "anyone can view location photos"
  on storage.objects for select
  using (bucket_id = 'location-photos');

drop policy if exists "anyone can upload a location photo" on storage.objects;
create policy "anyone can upload a location photo"
  on storage.objects for insert
  with check (bucket_id = 'location-photos');

-- Seed: import the 19 locations that already live in index.html, pre-approved.
insert into public.locations
  (id, name_ru, name_uk, district, district_name_ru, district_name_uk, type, format_ru, format_uk,
   is_paid, payment_note_ru, payment_note_uk, desc_ru, desc_uk, img, map_query, lat, lng, status)
values
  ('antalya_zoo', 'Antalya Zoo (Зоопарк)', 'Antalya Zoo (Зоопарк)', 'Kepez', 'Кепез', 'Кепез', 'nature', 'Природный зоопарк в сосновом лесу', 'Природний зоопарк у сосновому лісі', true, 'Платно. Билеты покупаются на кассе при входе/въезде.', 'Платно. Квитки купуються в касі при вході/в''їзді.', 'Огромный зоопарк с водоемами, пешеходными мостиками и свободными вольерами для животных. Есть детские площадки и большие пикник-зоны.', 'Величезний зоопарк із водоймами, пішохідними містками та просторими вольєрами для тварин. Є дитячі майданчики та великі зони для пікніків.', 'zoo.jpg.jpg', 'Antalya Zoo Kepez', 36.969, 30.632, 'approved'),
  ('dokumapark', 'Dokuma Park & Музей игрушек', 'Dokuma Park & Музей іграшок', 'Kepez', 'Кепез', 'Кепез', 'nature', 'Парковый комплекс с музеями и площадками', 'Парковий комплекс із музеями та майданчиками', false, 'Вход в парк бесплатный. Музеи — символическая плата.', 'Вхід до парку безкоштовний. Музеї — символічна плата.', 'Большой арт-парк на территории бывшей фабрики. Музей игрушек, музей миниатюр, ботанический сад, паровозики и площадки.', 'Великий арт-парк на території колишньої фабрики. Музей іграшок, музей мініатюр, ботанічний сад, поїзди та дитячі майданчики.', 'documa.jpg.jpg', 'Dokuma Park Kepez', 36.9205, 30.6815, 'approved'),
  ('park_funtastic', 'Park Funtastic', 'Park Funtastic', 'Kepez', 'Кепез', 'Кепез', 'nature', 'Парк развлечений и верёвочный городок', 'Парк розваг та мотузковий парк', true, 'Оплата за каждый аттракцион отдельно.', 'Оплата за кожен атракціон окремо.', 'Активный отдых на свежем воздухе: зиплайн, верёвочные трассы для разных возрастов, карусели, автодром и кафе.', 'Активний відпочинок на свіжому повітрі: зіплайн, мотузкові траси для різного віку, каруселі, автодром та кафе.', 'agaclar_ustunde_parkur.jpg.jpg', 'Park Funtastic Kepez', 36.945, 30.662, 'approved'),
  ('duden_upper', 'Парк Верхний Дюден', 'Парк Верхній Дюден', 'Kepez', 'Кепез', 'Кепез', 'nature', 'Природный парк с водопадом и пещерами', 'Природний парк із водоспадом та печерами', true, 'Символическая плата за вход.', 'Символічна плата за вхід.', 'Прохладный природный парк вокруг водопада. Можно зайти в пещеру прямо за падающей водой и погулять по тенистым аллеям.', 'Прохолодний природний парк навколо водоспаду. Можна зайти в печеру прямо за падаючою водою та погуляти тінистими алеями.', 'duden.jpg', 'Upper Duden Waterfalls', 36.963, 30.726, 'approved'),
  ('kepez_macera', 'Kepez Macera Ormanı (Лесной парк)', 'Kepez Macera Ormanı (Лісовий парк)', 'Kepez', 'Кепез', 'Кепез', 'nature', 'Лесной парк приключений и скалодром', 'Лісовий парк пригод та скалодром', true, 'Платно. Оплата полос препятствий.', 'Платно. Оплата смуг перешкод.', 'Сосновый парк в горах Кепеза. Верёвочные трассы для детей и взрослых, пейнтбол, стрельба из лука и смотровые площадки.', 'Сосновий парк у горах Кепеза. Мотузкові траси для дітей і дорослих, пейнтбол, стрільба з лука та оглядові майданчики.', 'https://images.unsplash.com/photo-1448375240586-882707db888b?auto=format&fit=crop&w=800&q=80', 'Kepez Macera Ormani', 36.958, 30.645, 'approved'),
  ('beach_park_konyaalti', 'Beach Park & Набережная', 'Beach Park & Набережна', 'Konyaalti', 'Коньяалты', 'Коньяалти', 'free', 'Набережная, скверы и спортивные площадки', 'Набережна, сквери та спортивні майданчики', false, 'Бесплатный вход и общественные площадки.', 'Безкоштовний вхід та громадські майданчики.', 'Просторная пешеходная набережная с современными детскими городками, скейт-парком, велосипедными дорожками и зелеными лужайками.', 'Простора пішоходна набережна з сучасними дитячими містечками, скейт-парком, велосипедними доріжками та зеленими галявинами.', 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=800&q=80', 'Konyaalti Beach Park', 36.877, 30.652, 'approved'),
  ('aktur_park', 'Aktur Park (Луна-парк)', 'Aktur Park (Місяць-парк)', 'Konyaalti', 'Коньяалты', 'Коньяалти', 'nature', 'Парк аттракционов и колесо обозрения', 'Парк атракціонів та колесо огляду', true, 'Оплата жетонами / картой парка.', 'Оплата жетонами / карткою парку.', 'Огромный луна-парк напротив ТЦ 5M Migros. Самое большое колесо обозрения в Турции Heart of Antalya, американские горки.', 'Величезний луна-парк навпроти ТЦ 5M Migros. Найбільше колесо огляду в Туреччині Heart of Antalya, американські гірки.', 'https://images.unsplash.com/photo-1560972550-aba3456b5564?auto=format&fit=crop&w=800&q=80', 'Aktur Park Konyaalti', 36.887, 30.66, 'approved'),
  ('antalya_aquarium', 'Antalya Aquarium & Снежный мир', 'Antalya Aquarium & Сніговий світ', 'Konyaalti', 'Коньяалты', 'Коньяалти', 'mall', 'Гигантский океанариум и развлекательный центр', 'Гігантський океанаріум та розважальний центр', true, 'Платно. Билеты в кассе или онлайн.', 'Платно. Квитки в касі або онлайн.', 'Один из самых длинных туннельных аквариумов в мире. Внутри есть зона со настоящим снегом Snow World, террариум и кинотеатр 4D.', 'Один із найдовших тунельних акваріумів у світі. Усередині є зона зі справжнім снігом Snow World, тераріум та кінотеатр 4D.', 'https://images.unsplash.com/photo-1544551763-46a013bb70d5?auto=format&fit=crop&w=800&q=80', 'Antalya Aquarium Konyaalti', 36.879, 30.659, 'approved'),
  ('hayat_park', 'Hayat Park Konyaaltı', 'Hayat Park Konyaaltı', 'Konyaalti', 'Коньяалты', 'Коньяалти', 'free', 'Большой лесопарк для семейных прогулок', 'Великий лісопарк для сімейних прогулянок', false, 'Бесплатный вход.', 'Безкоштовний вхід.', 'Огромный зеленый парк в Коньяалты с соснами, игровыми площадками, беговыми дорожками, теннисными кортами и уютными кафе.', 'Величезний зелений парк у Коньяалти з соснами, ігровими майданчиками, біговими доріжками, тенісними кортами та затишними кафе.', 'hayatpark.jpg.jpg', 'Hayat Park Konyaalti', 36.871, 30.612, 'approved'),
  ('vr_arena_konyaalti', 'VR Arena Konyaaltı', 'VR Arena Konyaaltı', 'Konyaalti', 'Коньяалты', 'Коньяалти', 'mall', 'Арена виртуальной реальности и VR-игры', 'Арена віртуальної реальності та VR-ігри', true, 'Платно. Оплата за сеансы / игровое время.', 'Платно. Оплата за сеанси / ігровий час.', 'Современная VR-арена для детей и подростков. Командные VR-игры, свободное перемещение без проводов, симуляторы и празднование дней рождения.', 'Сучасна VR-арена для дітей та підлітків. Командні VR-ігри, вільне переміщення без дротів, симулятори та святкування днів народження.', 'https://images.unsplash.com/photo-1592478411213-6153e4ebc07d?auto=format&fit=crop&w=800&q=80', 'VR Arena Konyaalti Antalya', 36.862, 30.628, 'approved'),
  ('karaalioglu_park', 'Karaalioglu Park', 'Парк Карааліоглу', 'Muratpasa', 'Муратпаша / Лара', 'Муратпаша / Лара', 'nature', 'Прибрежный исторический парк', 'Прибережний історичний парк', false, 'Бесплатный городской парк.', 'Безкоштовний міський парк.', 'Тенистый парк над обрывом с видом на море и старый город Калеичи. Большие игровые площадки, скульптуры и фонтаны.', 'Тінистий парк над урвищем із видом на море та старе місто Калеїчі. Великі ігрові майданчики, скульптури та фонтани.', 'karaaolu.jpg.jpg', 'Karaalioglu Park Antalya', 36.881, 30.706, 'approved'),
  ('kaleici_toy_museum', 'Музей игрушек в Калеичи (Oyuncak Müzesi)', 'Музей іграшок у Калеїчі (Oyuncak Müzesi)', 'Muratpasa', 'Муратпаша / Лара', 'Муратпаша / Лара', 'mall', 'Музей винтажных игрушек в старом порту', 'Музей вінтажних іграшок у старому порту', true, 'Символическая плата за вход.', 'Символічна плата за вхід.', 'Сказочный музей прямо в исторической гавани Калеичи (Marina) с коллекцией из тысяч игрушек разных эпох и стран со всего мира.', 'Казковий музей прямо в історичній гавані Калеїчі (Marina) з колекцією з тисяч іграшок різних епох і країн зі всього світу.', 'toy-museum1.jpg.webp', 'Antalya Toy Museum Kaleici', 36.8845, 30.7042, 'approved'),
  ('terracity_indoor', 'TerraCity Игровые зоны', 'TerraCity Ігрові зони', 'Muratpasa', 'Муратпаша / Лара', 'Муратпаша / Лара', 'mall', 'Крытый детский развлекательный центр', 'Закритий дитячий розважальний центр', true, 'Платно. Оплата по карте игровой зоны.', 'Платно. Оплата за карткою ігрової зони.', 'Развлекательные центры на верхнем этаже ТЦ: лабиринты, батуты, симуляторы и автоматы для детей любого возраста.', 'Розважальні центри на верхньому поверсі ТЦ: лабіринти, батути, симулятори та автомати для дітей будь-якого віку.', 'terracıtty play.jpg.jpg', 'TerraCity Antalya', 36.8528, 30.757, 'approved'),
  ('duden_lower', 'Парк Нижний Дюден & Водопад', 'Парк Нижній Дюден & Водоспад', 'Muratpasa', 'Муратпаша / Лара', 'Муратпаша / Лара', 'nature', 'Прибрежный парк у водопада, падающего в море', 'Прибережний парк біля водоспаду, що впадає в море', false, 'Бесплатный парк.', 'Безкоштовний парк.', 'Красивейший парк в районе Лара, где река Дюден с 40-метровой высоты срывается прямиком в Средиземное море. Детские площадки и велодорожки.', 'Найкрасивіший парк у районі Лара, де річка Дюден із 40-метрової висоти падає прямо в Середземне море. Дитячі майданчики та велодоріжки.', 'dunden нижний.jpg.jpg', 'Lower Duden Waterfall Park', 36.851, 30.784, 'approved'),
  ('selfie_park', 'Selfie Park Antalya (Селфи Парк)', 'Selfie Park Antalya (Селфі Парк)', 'Muratpasa', 'Муратпаша / Лара', 'Муратпаша / Лара', 'mall', 'Интерактивный музей фотолокаций и 3D-зон', 'Інтерактивний музей фотолокацій та 3D-зон', true, 'Платно. Входной билет на кассе.', 'Платно. Квитки в касі.', 'Крупнейший интерактивный инста-парк с 50+ яркими тематическими 3D-комнатами, профессиональным светом и фотозонами для детей.', 'Найбільший інтерактивний інста-парк із 50+ яскравими тематичними 3D-кімнатами, професійним світлом та фотозонами для дітей.', 'selfie-park.jpg.webp', 'Selfie Park Antalya', 36.8535, 30.7485, 'approved'),
  ('butterfly_park', 'Butterfly Park Antalya (Парк бабочек)', 'Butterfly Park Antalya (Парк метеликів)', 'Muratpasa', 'Муратпаша / Лара', 'Муратпаша / Лара', 'nature', 'Тропический сад с экзотическими бабочками', 'Тропічний сад з екзотичними метеликами', true, 'Платно. Входной билет на кассе.', 'Платно. Квитки в касі.', 'Крытый тропический ботанический купол с сотнями живых порхающих экзотических бабочек, редкими птицами, террариумом и детской зоной.', 'Закритий тропічний ботанічний купол із сотнями живих екзотичних метеликів, рідкісними птахами, тераріумом та дитячою зоною.', 'baterflyaı (1).webp', 'Kelebek Park Antalya Lara', 36.858, 30.852, 'approved'),
  ('vr_arena_lara', 'VR Arena Lara', 'VR Arena Lara', 'Muratpasa', 'Муратпаша / Лара', 'Муратпаша / Лара', 'mall', 'Арена виртуальной реальности и VR-игры', 'Арена віртуальної реальності та VR-ігри', true, 'Платно. Оплата за сеансы / игровое время.', 'Платно. Оплата за сеанси / ігровий час.', 'Интерактивная VR-площадка в районе Лара. Командные шутеры и квесты в виртуальной реальности, полное погружение для детей и взрослых.', 'Інтерактивний VR-майданчик у районі Лара. Командні шутери та квести у віртуальній реальності, повне занурення для дітей та дорослих.', 'vr lara.jpg.webp', 'VR Arena Lara Antalya', 36.856, 30.762, 'approved'),
  ('mall_of_antalya', 'Mall of Antalya & MOAPark', 'Mall of Antalya & MOAPark', 'Muratpasa', 'Муратпаша / Лара', 'Муратпаша / Лара', 'mall', 'Крупный ТРЦ с батутами и автодромом', 'Великий ТРЦ з батутами та автодромом', true, 'Оплата игровых аттракционов.', 'Оплата ігрових атракціонів.', 'Огромная крытая детская игровая зона, скалодром, батутный центр и фудкорт с семейной зоной рядом с аэропортом.', 'Величезна закрита дитяча ігрова зона, скалодром, батутний центр та фудкорт із сімейною зоною поруч із аеропортом.', 'https://images.unsplash.com/photo-1519567241046-7f570eee3ce6?auto=format&fit=crop&w=800&q=80', 'Mall of Antalya', 36.918, 30.785, 'approved'),
  ('land_of_legends', 'The Land of Legends Theme Park', 'The Land of Legends Theme Park', 'Serik', 'Белек / Серик', 'Белек / Серік', 'nature', 'Тематический парк и аквапарк', 'Тематичний парк та аквапарк', true, 'Платно. Билеты в тематическую зону.', 'Платно. Квитки у тематичну зону.', 'Грандиозный турецкий Диснейленд с захватывающими американскими горками, огромным аквапарком, шоу дельфинов и вечерними парадами.', 'Грандіозний турецький Діснейленд із захоплюючими американськими гірками, величезним аквапарком, шоу дельфінів та вечірніми парадами.', 'land-of-legends.jpg.jpg', 'The Land of Legends Theme Park', 36.876, 31.002, 'approved')
on conflict (id) do nothing;
