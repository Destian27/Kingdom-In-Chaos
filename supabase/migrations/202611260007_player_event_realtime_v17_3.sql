-- Kingdom in Chaos DTP v17.3 Realtime publication (incremental migration).
-- Use only for an existing project that already has the complete v17.2 schema.
-- Fresh installs should run the single canonical SQL-GABUNGAN-v17.4-ALL-IN-ONE.sql.
begin;
do $migration_007$
declare
  v_table text;
  v_tables text[] := array[
    'game_profiles',
    'game_player_saves',
    'game_admin_player_economy',
    'game_event_store_config',
    'game_event_store_items',
    'game_cave_boss_hourly_schedule',
    'game_cave_boss_override'
  ];
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise exception 'Publication supabase_realtime is missing. Enable Realtime in Supabase and rerun migration 007.';
  end if;

  foreach v_table in array v_tables loop
    if to_regclass('public.' || v_table) is null then
      raise exception 'Required table public.% is missing. Complete v17.2 / migration 006 first.', v_table;
    end if;
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = v_table
    ) then
      execute format('alter publication supabase_realtime add table public.%I', v_table);
    end if;
    execute format('alter table public.%I replica identity full', v_table);
  end loop;
end
$migration_007$;
commit;
