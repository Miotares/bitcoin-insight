-- Bitcoin Insight — daily historical BTC price (multi-currency)
-- Applied to Supabase project `bitcoin-insight` (hyyagnnsjbpsehriyafn) via MCP.
-- This file is the canonical reference; re-runnable.
--
-- Purpose: mempool.space's /api/v1/historical-price is hourly for the recent
-- window but coarsens to ~weekly far in the past, so the long-range (1Y / All)
-- chart looks sparse. This table holds a DENSE DAILY series back to 2011 to
-- enrich it; the app keeps serving recent days from mempool and blends at the
-- seam (same date → same daily close).
--
-- Data methodology (see supabase/functions/backfill-price-history):
--   BTC/USD daily close ....... Bitstamp /api/v2/ohlc/btcusd (from 2011-09-01)
--   USD -> EUR/GBP/CHF/CAD/AUD/JPY .. ECB EUR-base reference rates
--       price_CUR = price_USD * ecb[CUR] / ecb[USD]
--       (ECB rates forward-filled over weekends/holidays)
-- BTC has one global price (BTC/USD); fiat display is BTC/USD x FX — the same
-- approach mempool itself uses (its response carries an `exchangeRates` object).
--
-- LICENSING (production TODO): the FX layer (ECB / frankfurter) is public/open.
-- The BTC/USD source (Bitstamp) permits commercial redistribution in principle
-- but gates it behind a signed Data License Agreement (partners@bitstamp.net) —
-- confirm before serving to end users. The backfill fn is source-agnostic: only
-- the BTC/USD fetch changes.

-- Table (wide: one row per UTC day, one column per currency) -----------------
create table if not exists public.price_history (
    day    date primary key,        -- UTC calendar day
    usd    double precision,        -- BTC close in each currency
    eur    double precision,
    gbp    double precision,
    chf    double precision,
    cad    double precision,
    aud    double precision,
    jpy    double precision,
    source text                     -- provenance, e.g. 'bitstamp+ecb'
);

-- Read-only RLS, same pattern as public.network_stats / public.fees_history ---
alter table public.price_history enable row level security;

drop policy if exists price_history_read on public.price_history;
create policy price_history_read
    on public.price_history
    for select
    to anon, authenticated
    using (true);

grant select on public.price_history to anon, authenticated;

-- Backfill / daily top-up ----------------------------------------------------
-- Run by the `backfill-price-history` Edge Function (idempotent upsert on `day`).
-- One-time backfill done 2026-06-23: 5410 rows, 2011-09-01 -> present.
-- For a daily top-up, schedule the same function (it re-upserts; cheap), e.g.:
--   select cron.schedule('append-price-history', '15 1 * * *',
--     $$ select net.http_post(
--          url := 'https://hyyagnnsjbpsehriyafn.supabase.co/functions/v1/backfill-price-history',
--          headers := '{"Content-Type":"application/json"}'::jsonb) $$);
-- (requires the pg_net extension; alternatively use Supabase scheduled functions.)
--
-- NOTE: the function is currently deployed with verify_jwt=false for the one-time
-- backfill — for production, secure it (a shared-secret header or schedule-only)
-- or remove it after the daily-append path is wired up.

-- App/widget read contract:
--   GET https://hyyagnnsjbpsehriyafn.supabase.co/rest/v1/price_history
--       ?select=day,<cur>           -- e.g. select=day,eur
--       &day=gte.<iso-date>
--       &order=day.asc
--   header apikey: <publishable key>
