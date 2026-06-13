-- Bitcoin Insight — widget stats cache
-- Applied to Supabase project `bitcoin-insight` (hyyagnnsjbpsehriyafn) via MCP.
-- This file is the canonical reference; re-runnable.
--
-- Purpose: ONLY the iOS widgets read from this backend. The app stays direct
-- to mempool.space. A single pg_cron job (every minute) fetches a small bundle
-- of global stats and upserts one row; widgets read it with the anon key.

-- Extensions ----------------------------------------------------------------
create extension if not exists http with schema extensions;  -- sync HTTP client
create extension if not exists pg_cron;                      -- minute scheduler

-- Table ---------------------------------------------------------------------
-- Single cached row (id = 1).
create table if not exists public.network_stats (
    id integer primary key default 1 check (id = 1),
    payload jsonb not null,
    updated_at timestamptz not null default now()
);

alter table public.network_stats enable row level security;

-- Widgets read with the anon key; read-only, no write policy.
drop policy if exists "network_stats read" on public.network_stats;
create policy "network_stats read"
    on public.network_stats
    for select
    to anon, authenticated
    using (true);

-- Writer --------------------------------------------------------------------
-- Fetches mempool.space, bundles a small payload, upserts row 1.
-- Per-source error handling keeps prior good values if a fetch fails this run,
-- so a transient mempool outage never nulls out good data.
create or replace function public.refresh_network_stats()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_prices   jsonb;
    v_height   bigint;
    v_fees     jsonb;
    v_existing jsonb;
    v_payload  jsonb;
begin
    select payload into v_existing from public.network_stats where id = 1;

    perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', '4000');

    begin
        select (extensions.http_get('https://mempool.space/api/v1/prices')).content::jsonb
          into v_prices;
    exception when others then v_prices := null;
    end;

    begin
        select trim(both from (extensions.http_get('https://mempool.space/api/blocks/tip/height')).content)::bigint
          into v_height;
    exception when others then v_height := null;
    end;

    begin
        select (extensions.http_get('https://mempool.space/api/v1/fees/recommended')).content::jsonb
          into v_fees;
    exception when others then v_fees := null;
    end;

    v_payload := jsonb_build_object(
        'prices', coalesce(
            case when v_prices is not null then jsonb_build_object(
                'USD', v_prices->'USD', 'EUR', v_prices->'EUR', 'GBP', v_prices->'GBP',
                'CAD', v_prices->'CAD', 'CHF', v_prices->'CHF', 'AUD', v_prices->'AUD',
                'JPY', v_prices->'JPY'
            ) end,
            v_existing->'prices'),
        'blockHeight', coalesce(to_jsonb(v_height), v_existing->'blockHeight'),
        'fees', coalesce(
            case when v_fees is not null then jsonb_build_object(
                'fast', v_fees->'fastestFee',
                'halfHour', v_fees->'halfHourFee',
                'hour', v_fees->'hourFee'
            ) end,
            v_existing->'fees')
    );

    insert into public.network_stats (id, payload, updated_at)
    values (1, v_payload, now())
    on conflict (id) do update
        set payload = excluded.payload,
            updated_at = excluded.updated_at;
end;
$$;

-- Only the scheduler (postgres) may run the writer — not anon/authenticated.
revoke execute on function public.refresh_network_stats() from anon, authenticated, public;

-- Schedule ------------------------------------------------------------------
-- Re-runnable: drop any existing job of the same name, then schedule + seed.
do $$ begin
  perform cron.unschedule('refresh-network-stats');
exception when others then null; end $$;

select cron.schedule('refresh-network-stats', '* * * * *', 'select public.refresh_network_stats();');
select public.refresh_network_stats();  -- seed immediately

-- Read contract (widget):
--   GET https://hyyagnnsjbpsehriyafn.supabase.co/rest/v1/network_stats?select=payload,updated_at&id=eq.1
--   header: apikey: <anon or publishable key>
