-- Kingdom In Chaos DTP v17.14.16 — kredensial Daftar (Nama Pengguna + Kata Sandi)
-- Jalankan SEKALI di Supabase SQL Editor, SEBELUM deploy google-player v17.14.16.
-- Kata sandi TIDAK disimpan polos: hanya hash PBKDF2-SHA256 + salt. Tabel hanya bisa diakses service_role.
begin;

create table if not exists public.game_google_player_credentials (
  player_uuid uuid primary key references public.game_google_players(player_uuid) on delete cascade,
  password_hash text not null,
  password_salt text not null,
  password_iterations integer not null default 100000 check (password_iterations >= 10000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.game_google_player_credentials enable row level security;
revoke all on public.game_google_player_credentials from public, anon, authenticated;
grant select, insert, update, delete on public.game_google_player_credentials to service_role;

commit;
