-- Trainingslog: database voor Kristiaan en Rutger
-- Plak dit volledige script in Supabase > SQL Editor en klik op Run.

create table if not exists tl_config (
  id int primary key default 1 check (id = 1),
  pin text not null
);

create table if not exists tl_days (
  id text primary key,
  name text not null,
  ord int not null default 0,
  exercises jsonb not null default '[]'::jsonb
);

create table if not exists tl_logs (
  id text primary key,
  person text not null,
  exercise text not null,
  ex_key text not null,
  rounds jsonb not null default '[]'::jsonb,
  kg numeric,
  sets int,
  reps int,
  note text not null default '',
  date date not null,
  day_name text not null default '',
  ts bigint not null
);

create index if not exists tl_logs_date_idx on tl_logs (date desc, ts desc);

-- Tabellen zijn alleen bereikbaar via de functies hieronder, met de pincode.
alter table tl_config enable row level security;
alter table tl_days enable row level security;
alter table tl_logs enable row level security;
revoke all on tl_config, tl_days, tl_logs from anon, authenticated;

create or replace function tl_check(p_pin text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_pin is null or not exists (select 1 from tl_config where pin = p_pin) then
    perform pg_sleep(1);
    raise exception 'pin_onjuist';
  end if;
end $$;

create or replace function tl_status() returns json
language sql security definer set search_path = public as $$
  select json_build_object('hasPin', exists (select 1 from tl_config));
$$;

create or replace function tl_set_pin(p_pin text) returns json
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from tl_config) then raise exception 'pin_bestaat_al'; end if;
  if length(coalesce(p_pin, '')) < 6 then raise exception 'pin_te_kort'; end if;
  insert into tl_config (id, pin) values (1, p_pin);
  return json_build_object('ok', true);
end $$;

create or replace function tl_load(p_pin text) returns json
language plpgsql security definer set search_path = public as $$
begin
  perform tl_check(p_pin);
  return json_build_object(
    'days', (select coalesce(json_agg(d order by d.ord), '[]'::json) from tl_days d),
    'logs', (select coalesce(json_agg(l), '[]'::json) from (
               select * from tl_logs order by date desc, ts desc limit 3000) l)
  );
end $$;

create or replace function tl_save_log(p_pin text, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform tl_check(p_pin);
  insert into tl_logs (id, person, exercise, ex_key, rounds, kg, sets, reps, note, date, day_name, ts)
  values (p->>'id', p->>'person', p->>'exercise', p->>'ex_key', coalesce(p->'rounds', '[]'::jsonb),
          (p->>'kg')::numeric, (p->>'sets')::int, (p->>'reps')::int, coalesce(p->>'note', ''),
          (p->>'date')::date, coalesce(p->>'day_name', ''), (p->>'ts')::bigint)
  on conflict (id) do update set
    person = excluded.person, exercise = excluded.exercise, ex_key = excluded.ex_key,
    rounds = excluded.rounds, kg = excluded.kg, sets = excluded.sets, reps = excluded.reps,
    note = excluded.note, date = excluded.date, day_name = excluded.day_name, ts = excluded.ts;
end $$;

create or replace function tl_delete_log(p_pin text, p_id text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform tl_check(p_pin);
  delete from tl_logs where id = p_id;
end $$;

create or replace function tl_save_day(p_pin text, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform tl_check(p_pin);
  insert into tl_days (id, name, ord, exercises)
  values (p->>'id', p->>'name', coalesce((p->>'ord')::int, 0), coalesce(p->'exercises', '[]'::jsonb))
  on conflict (id) do update set name = excluded.name, ord = excluded.ord, exercises = excluded.exercises;
end $$;

create or replace function tl_delete_day(p_pin text, p_id text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform tl_check(p_pin);
  delete from tl_days where id = p_id;
end $$;

revoke execute on function tl_check(text) from public, anon, authenticated;
grant execute on function tl_status(), tl_set_pin(text), tl_load(text), tl_save_log(text, jsonb),
  tl_delete_log(text, text), tl_save_day(text, jsonb), tl_delete_day(text, text) to anon;

-- Jullie vaste schema
insert into tl_days (id, name, ord, exercises) values
('maandag', 'Maandag', 1, '["Liggende Leg Curl","Barbell Back Squat","Hyperextension for Glutes","Flat Dumbbell Press","Lat Pulldowns","Machine Shoulder Press","One Arm Dumbbell Preacher Curls","Dual Rope Pushdown","Crunch"]'),
('woensdag', 'Woensdag', 2, '["Bodyweight Lunges","Barbell Romanian Deadlift","Bulgarian Split Squats","Standing Military Press","Chest Supported Row","Incline Dumbbell Press","Cross Cable Triceps Extensions","Incline Dumbbell Curl","Standing Calf Raises"]'),
('vrijdag', 'Vrijdag', 3, '["Liggende Leg Curl","Leg Press, feet low","Dumbbell Romanian Deadlift","Front Lat Pulldown","Flat Dumbbell Press","Dumbbell Y Raise","Liggende Dumbbell Triceps Extensions","Dumbbell Hammer Curl","Reverse Crunch"]')
on conflict (id) do nothing;

notify pgrst, 'reload schema';
