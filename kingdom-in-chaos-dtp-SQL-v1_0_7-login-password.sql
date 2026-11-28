-- Kingdom In Chaos DTP v1.0.7 — login Nama Pengguna + Kata Sandi (Google dihapus total)
-- Jalankan SEKALI di Supabase SQL Editor, SEBELUM mengganti kode Edge Function google-player.
-- Aman dijalankan ulang. Kata sandi TIDAK disimpan polos: hanya hash PBKDF2-SHA256 + salt.
begin;

create table if not exists public.game_google_player_credentials (
  player_uuid uuid primary key references public.game_google_players(player_uuid) on delete cascade,
  password_hash text not null,
  password_salt text not null,
  password_iterations integer not null default 100000 check (password_iterations >= 10000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Pembatas percobaan salah: 5 kali salah -> terkunci 5 menit.
alter table public.game_google_player_credentials
  add column if not exists failed_attempts integer not null default 0,
  add column if not exists locked_until timestamptz;

alter table public.game_google_player_credentials enable row level security;
revoke all on public.game_google_player_credentials from public, anon, authenticated;
grant select, insert, update, delete on public.game_google_player_credentials to service_role;

-- Nama pengguna unik tanpa membedakan huruf besar/kecil (sudah ada di SQL lama; dijaga di sini).
create unique index if not exists game_google_players_nickname_ci_uq
  on public.game_google_players(lower(nickname)) where nickname is not null;

commit;
