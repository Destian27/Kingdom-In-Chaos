-- Jalankan setelah migration 202611260003_admin_player_management.sql.
-- 1) Ganti YOUR_ADMIN_EMAIL dengan email akun yang sudah ada di Supabase Auth.
-- 2) Jalankan blok INSERT, lalu jalankan SELECT verifikasi di bawah.

insert into public.game_admin_users (user_id, role, active)
select id, 'super_admin', true
from auth.users
where lower(email) = lower('YOUR_ADMIN_EMAIL')
on conflict (user_id) do update
set role = 'super_admin', active = true;

-- Verifikasi: hasil harus menampilkan email admin dan active = true.
select a.user_id, u.email, a.role, a.active, a.created_at
from public.game_admin_users a
join auth.users u on u.id = a.user_id
order by a.created_at desc;
