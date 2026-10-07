-- Placeholder cards (set 'test') so pulls work before real art exists. Replace via the art import.
insert into public.cards (id, name, rarity, set_id, art_path) values
  ('test-common-01','Test Common A','common','test','placeholder/common.png'),
  ('test-common-02','Test Common B','common','test','placeholder/common.png'),
  ('test-rare-01','Test Rare A','rare','test','placeholder/rare.png'),
  ('test-rare-02','Test Rare B','rare','test','placeholder/rare.png'),
  ('test-epic-01','Test Epic A','epic','test','placeholder/epic.png'),
  ('test-legendary-01','Test Legendary A','legendary','test','placeholder/legendary.png');

insert into public.banners (id, name, cost_single, cost_ten) values ('standard','Standard Pack',160,1600);
insert into public.banner_cards (banner_id, card_id) select 'standard', id from public.cards where set_id = 'test';
