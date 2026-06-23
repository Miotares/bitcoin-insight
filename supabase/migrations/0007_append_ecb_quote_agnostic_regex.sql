-- Bitcoin Insight — fix append_price_history_recent() ECB parsing
-- Applied to Supabase project `bitcoin-insight` (hyyagnnsjbpsehriyafn) via MCP.
-- This file is the canonical reference; re-runnable.
--
-- Bug: the ECB eurofxref-DAILY file uses single-quoted attributes
--   <Cube currency='USD' rate='1.13'/>
-- while the HIST file (used by the backfill Edge Function) uses double quotes.
-- append_price_history_recent() regexed double quotes only, so the daily top-up
-- silently matched 0 currencies and never wrote a row (the daily cron appeared to
-- run but was a no-op). The full history existed only because the Edge Function
-- backfill reads the double-quoted hist file.
--
-- Fix: make the currency/rate regex quote-agnostic so the daily cron actually
-- populates all currencies (7 originals + 9 Tier-1 additions) going forward.

create or replace function public.append_price_history_recent()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_bs    jsonb;
    v_ecb   text;
    v_rates jsonb;
    v_usd_per_eur double precision;
    c record;
begin
    perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', '8000');

    begin
        select (extensions.http_get('https://www.bitstamp.net/api/v2/ohlc/btcusd/?step=86400&limit=5')).content::jsonb
          into v_bs;
    exception when others then return; end;

    begin
        select (extensions.http_get('https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml')).content
          into v_ecb;
    exception when others then return; end;

    -- Quote-agnostic: the daily XML uses single quotes, the hist XML double.
    select jsonb_object_agg(arr[1], to_jsonb(arr[2]::double precision))
      into v_rates
      from (select regexp_matches(v_ecb, 'currency=["'']([A-Z]{3})["'']\s+rate=["'']([0-9.]+)["'']', 'g') as arr) s;

    v_usd_per_eur := (v_rates->>'USD')::double precision;
    if v_usd_per_eur is null or v_bs is null then return; end if;

    for c in
        select to_timestamp((e->>'timestamp')::bigint)::date as day,
               (e->>'close')::double precision as close
        from jsonb_array_elements(v_bs->'data'->'ohlc') as e
    loop
        if c.close is null or c.close <= 0 then continue; end if;
        insert into public.price_history
            (day, usd, eur, gbp, chf, cad, aud, jpy,
             brl, inr, mxn, krw, thb, idr, "try", czk, pln, source)
        values (
            c.day, c.close,
            c.close / v_usd_per_eur,
            c.close * (v_rates->>'GBP')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'CHF')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'CAD')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'AUD')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'JPY')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'BRL')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'INR')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'MXN')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'KRW')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'THB')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'IDR')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'TRY')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'CZK')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'PLN')::double precision / v_usd_per_eur,
            'bitstamp+ecb'
        )
        on conflict (day) do update set
            usd=excluded.usd, eur=excluded.eur, gbp=excluded.gbp, chf=excluded.chf,
            cad=excluded.cad, aud=excluded.aud, jpy=excluded.jpy,
            brl=excluded.brl, inr=excluded.inr, mxn=excluded.mxn, krw=excluded.krw,
            thb=excluded.thb, idr=excluded.idr, "try"=excluded."try",
            czk=excluded.czk, pln=excluded.pln, source=excluded.source;
    end loop;
end;
$$;

revoke execute on function public.append_price_history_recent() from anon, authenticated, public;
