-- Per-tick history of mempool count / USD price / hashrate, used to draw tiny
-- 24h (mempool, price/moscow) and 30d (hashrate) sparklines on the Home widgets.

create table if not exists public.network_stats_history (
    id            bigint generated always as identity primary key,
    recorded_at   timestamptz not null default now(),
    mempool_count integer,
    price_usd     double precision,
    hashrate      double precision
);

create index if not exists network_stats_history_recorded_at_idx
    on public.network_stats_history (recorded_at desc);

-- Lock it down: RLS on, NO policy here -> no direct PostgREST access until the
-- harden migration adds an explicit read-only policy. The downsampled series is
-- exposed through the RPC below.
alter table public.network_stats_history enable row level security;

-- Append one row from the current network_stats snapshot (the row the every-minute
-- refresh already wrote -> no extra HTTP). Also prunes anything older than 35 days
-- (covers the 30-day hashrate window with headroom).
create or replace function public.snapshot_network_stats()
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
    insert into public.network_stats_history (recorded_at, mempool_count, price_usd, hashrate)
    select now(),
           nullif(payload->>'mempoolCount','')::integer,
           nullif(payload->'prices'->>'USD','')::double precision,
           nullif(payload->>'hashrate','')::double precision
    from public.network_stats
    where id = 1;

    delete from public.network_stats_history
    where recorded_at < now() - interval '35 days';
end;
$$;

-- One call returns all three downsampled arrays (oldest -> newest):
--   mempool  : last 24h, <=48 points
--   priceUsd : last 24h, <=48 points   (Moscow Time = 100M / price, shape is the inverse)
--   hashrate : last 30d, <=40 points
-- width_bucket downsampling mirrors public.fees_history_series.
create or replace function public.network_stats_sparklines()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
    with cfg as (select now() as t_now),
    src24 as (
        select recorded_at, extract(epoch from recorded_at) as ep, mempool_count, price_usd
        from public.network_stats_history, cfg
        where recorded_at >= cfg.t_now - interval '24 hours'
    ),
    b24 as (select min(ep) lo, max(ep) hi from src24),
    bk24 as (
        select src24.*, case when b24.hi > b24.lo
               then width_bucket(src24.ep, b24.lo, b24.hi, 48) else 1 end as bk
        from src24, b24
    ),
    ds24 as (
        select distinct on (bk) bk, mempool_count, price_usd
        from bk24 order by bk, recorded_at desc
    ),
    src30 as (
        select recorded_at, extract(epoch from recorded_at) as ep, hashrate
        from public.network_stats_history, cfg
        where recorded_at >= cfg.t_now - interval '30 days' and hashrate is not null
    ),
    b30 as (select min(ep) lo, max(ep) hi from src30),
    bk30 as (
        select src30.*, case when b30.hi > b30.lo
               then width_bucket(src30.ep, b30.lo, b30.hi, 40) else 1 end as bk
        from src30, b30
    ),
    ds30 as (
        select distinct on (bk) bk, hashrate from bk30 order by bk, recorded_at desc
    )
    select jsonb_build_object(
        'mempool',  coalesce((select jsonb_agg(mempool_count order by bk) from ds24 where mempool_count is not null), '[]'::jsonb),
        'priceUsd', coalesce((select jsonb_agg(price_usd     order by bk) from ds24 where price_usd is not null),     '[]'::jsonb),
        'hashrate', coalesce((select jsonb_agg(hashrate      order by bk) from ds30 where hashrate is not null),      '[]'::jsonb)
    );
$$;

revoke all on function public.network_stats_sparklines() from public;
grant execute on function public.network_stats_sparklines() to anon, authenticated;

-- Snapshot every 10 minutes (same cadence as snapshot-fees).
select cron.schedule('snapshot-network-stats', '*/10 * * * *', 'select public.snapshot_network_stats();');
