update public.app_maintenance
set is_active = true,
    title = 'SEDANG MAINTENANCE',
    message = 'Kami sedang memperbaiki server. Terima kasih sudah menunggu.',
    start_at = null,
    end_at = now() + interval '1 day 2 hours 30 minutes'
where id = 1;

update public.app_maintenance
set is_active = true,
    end_at = '2026-12-01 14:00:00+07'
where id = 1;

update public.app_maintenance
set is_active = true,
    end_at = null
where id = 1;

update public.app_maintenance
set is_active = false
where id = 1;
