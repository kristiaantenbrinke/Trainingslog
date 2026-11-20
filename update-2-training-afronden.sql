-- Trainingslog update 2: training afronden
-- Plak dit script in Supabase > SQL Editor en klik op Run. Eenmalig.

create table if not exists tl_sessions (
  id text primary key,
  person text not null,
  day_id text not null,
  day_name text not null default '',
  date date not null,
  done_at bigint not null
);
alter table tl_sessions enable row level security;
revoke all on tl_sessions from anon, authenticated;

create or replace function tl_load(p_pin text) returns json
language plpgsql security definer set search_path = public as $$
begin
  perform tl_check(p_pin);
  return json_build_object(
    'days', (select coalesce(json_agg(d order by d.ord), '[]'::json) from tl_days d),
    'logs', (select coalesce(json_agg(l), '[]'::json) from (
               select * from tl_logs order by date desc, ts desc limit 3000) l),
    'sessions', (select coalesce(json_agg(s), '[]'::json) from (
               select * from tl_sessions order by date desc limit 1000) s)
  );
end $$;

create or replace function tl_save_session(p_pin text, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform tl_check(p_pin);
  insert into tl_sessions (id, person, day_id, day_name, date, done_at)
  values (p->>'id', p->>'person', p->>'day_id', coalesce(p->>'day_name', ''), (p->>'date')::date, (p->>'done_at')::bigint)
  on conflict (id) do update set person = excluded.person, day_id = excluded.day_id,
    day_name = excluded.day_name, date = excluded.date, done_at = excluded.done_at;
end $$;

create or replace function tl_delete_session(p_pin text, p_id text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform tl_check(p_pin);
  delete from tl_sessions where id = p_id;
end $$;

grant execute on function tl_save_session(text, jsonb), tl_delete_session(text, text) to anon;

notify pgrst, 'reload schema';
