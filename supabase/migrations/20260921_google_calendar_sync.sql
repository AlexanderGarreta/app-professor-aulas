alter table public.aulas
  add column if not exists google_event_id text,
  add column if not exists google_calendar_id text default 'primary',
  add column if not exists google_account_email text,
  add column if not exists google_sync_status text not null default 'pendente',
  add column if not exists google_sync_action text not null default 'upsert',
  add column if not exists google_sync_error text,
  add column if not exists google_synced_at timestamptz;

create unique index if not exists aulas_google_event_id_unique
  on public.aulas (google_event_id)
  where google_event_id is not null;

update public.aulas
set
  google_sync_status = coalesce(google_sync_status, 'pendente'),
  google_sync_action = coalesce(google_sync_action, 'upsert'),
  google_calendar_id = coalesce(google_calendar_id, 'primary');

comment on column public.aulas.google_event_id is
  'ID do evento correspondente no Google Calendar.';
comment on column public.aulas.google_sync_status is
  'Estado da sincronização: pendente, sincronizando, sincronizado ou erro.';
comment on column public.aulas.google_sync_action is
  'Próxima ação: upsert ou delete.';
