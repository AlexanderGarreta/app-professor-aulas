create extension if not exists pgcrypto with schema extensions;

alter table public.aulas
  add column if not exists pacote_compra_id bigint,
  add column if not exists duracao_min integer,
  add column if not exists serie_id uuid,
  add column if not exists confirmacao_automatica boolean not null default false,
  add column if not exists realizada_em timestamptz;

alter table public.pacotes_comprados
  add column if not exists qtd_aulas_total integer,
  add column if not exists duracao_min integer,
  add column if not exists status_pacote text not null default 'Aberto';

alter table public.cobrancas
  add column if not exists pacote_compra_id bigint;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'aulas_pacote_compra_id_fkey'
  ) then
    alter table public.aulas
      add constraint aulas_pacote_compra_id_fkey
      foreign key (pacote_compra_id)
      references public.pacotes_comprados(id)
      on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'cobrancas_pacote_compra_id_fkey'
  ) then
    alter table public.cobrancas
      add constraint cobrancas_pacote_compra_id_fkey
      foreign key (pacote_compra_id)
      references public.pacotes_comprados(id)
      on delete set null;
  end if;
end $$;

update public.aulas a
set duracao_min = p.duracao_min
from public.pacotes_professor p
where a.duracao_min is null
  and p.nome_pacote = a.pacote;

update public.aulas set duracao_min = 60 where duracao_min is null;

update public.pacotes_comprados pc
set
  qtd_aulas_total = coalesce(pc.qtd_aulas_total, p.qtd_aulas),
  duracao_min = coalesce(pc.duracao_min, p.duracao_min)
from public.pacotes_professor p
where p.nome_pacote = pc.pacote;

create index if not exists aulas_pacote_compra_id_idx
  on public.aulas (pacote_compra_id);
create index if not exists aulas_serie_id_idx on public.aulas (serie_id);
create index if not exists aulas_data_status_idx
  on public.aulas (data_aula, status_aula);

create or replace function public.finalizar_aulas_passadas()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  quantidade integer;
begin
  update public.aulas
  set
    status_aula = 'Realizada',
    confirmacao_automatica = true,
    realizada_em = now()
  where status_aula = 'Agendada'
    and (
      to_date(data_aula, 'DD/MM/YYYY') + horario::time
      + make_interval(mins => coalesce(duracao_min, 60))
    ) <= timezone('America/Sao_Paulo', now());

  get diagnostics quantidade = row_count;
  return quantidade;
end;
$$;

grant execute on function public.finalizar_aulas_passadas() to anon, authenticated;

do $$
declare
  job_id bigint;
begin
  begin
    create extension if not exists pg_cron with schema extensions;
  exception when others then
    raise notice 'pg_cron não pôde ser habilitado automaticamente.';
  end;

  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    for job_id in select jobid from cron.job
      where jobname = 'profeconomy-finalizar-aulas'
    loop
      perform cron.unschedule(job_id);
    end loop;

    perform cron.schedule(
      'profeconomy-finalizar-aulas',
      '* * * * *',
      'select public.finalizar_aulas_passadas();'
    );
  end if;
end $$;
