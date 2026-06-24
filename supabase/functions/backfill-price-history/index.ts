// Edge Function: backfill-price-history
// Builds a daily multi-currency BTC price series and upserts it into
// public.price_history. BTC/USD daily close from Bitstamp (paginated), converted
// to the other currencies via ECB EUR-base reference rates
// (price_CUR = price_USD * ecb[CUR] / ecb[USD]; ECB rates forward-filled over
// weekends/holidays). Idempotent (upsert on `day`), so it doubles as a re-runnable
// backfill and a daily top-up. Writes with the service role (bypasses read-only RLS).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Non-USD/EUR ECB crosses. USD + EUR are handled explicitly below.
// Tier-1 additions (BRL…PLN) and CNY/HKD/SEK are all in the ECB reference set.
const CURS = [
  "GBP", "CHF", "CAD", "AUD", "JPY",
  "BRL", "INR", "MXN", "KRW", "THB", "IDR", "TRY", "CZK", "PLN",
  "CNY", "HKD", "SEK",
];

async function fetchBitstamp(): Promise<Map<string, number>> {
  const out = new Map<string, number>();
  let start = 1314835200; // 2011-09-01
  for (let i = 0; i < 40; i++) {
    const url =
      `https://www.bitstamp.net/api/v2/ohlc/btcusd/?step=86400&limit=1000&start=${start}`;
    const res = await fetch(url, { headers: { "User-Agent": "Mozilla/5.0" } });
    const rows = (await res.json())?.data?.ohlc ?? [];
    if (!rows.length) break;
    for (const c of rows) {
      const close = parseFloat(c.close);
      if (close > 0) {
        const day = new Date(parseInt(c.timestamp, 10) * 1000)
          .toISOString().slice(0, 10);
        out.set(day, close);
      }
    }
    const last = parseInt(rows[rows.length - 1].timestamp, 10);
    const nxt = last + 86400;
    if (nxt <= start) break;
    start = nxt;
    if (last * 1000 >= Date.now()) break;
  }
  return out;
}

async function fetchECB(): Promise<
  { days: string[]; rates: Map<string, Record<string, number>> }
> {
  const xml = await (await fetch(
    "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist.xml",
  )).text();
  const rates = new Map<string, Record<string, number>>();
  // Each day = <Cube time="YYYY-MM-DD"> ...self-closing currency cubes... </Cube>.
  // Quote-agnostic: the hist file uses double quotes, the daily file single quotes.
  const dayRe = /<Cube time=["'](\d{4}-\d{2}-\d{2})["']>([\s\S]*?)<\/Cube>/g;
  let m: RegExpExecArray | null;
  while ((m = dayRe.exec(xml)) !== null) {
    const r: Record<string, number> = {};
    const curRe = /currency=["']([A-Z]{3})["']\s+rate=["']([0-9.]+)["']/g;
    let c: RegExpExecArray | null;
    while ((c = curRe.exec(m[2])) !== null) r[c[1]] = parseFloat(c[2]);
    // Keep any day with at least USD; a currency missing on a given day (early
    // history before the ECB added it) is left null rather than dropping the day.
    if (r.USD) rates.set(m[1], r);
  }
  return { days: [...rates.keys()].sort(), rates };
}

function fxFor(
  day: string,
  days: string[],
  rates: Map<string, Record<string, number>>,
): Record<string, number> | null {
  let lo = 0, hi = days.length - 1, ans = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (days[mid] <= day) (ans = mid, lo = mid + 1);
    else hi = mid - 1;
  }
  return ans >= 0 ? rates.get(days[ans])! : null;
}

Deno.serve(async () => {
  try {
    const [btc, ecb] = await Promise.all([fetchBitstamp(), fetchECB()]);
    const rows: Record<string, unknown>[] = [];
    for (const day of [...btc.keys()].sort()) {
      const fx = fxFor(day, ecb.days, ecb.rates);
      if (!fx || !fx.USD) continue;
      const usd = btc.get(day)!;
      // Fixed key set on every row (null when a currency is missing that day) so
      // the bulk upsert stays column-consistent.
      const row: Record<string, unknown> = {
        day, usd, eur: usd / fx.USD, source: "bitstamp+ecb",
      };
      for (const k of CURS) {
        row[k.toLowerCase()] = (fx[k] != null) ? usd * fx[k] / fx.USD : null;
      }
      rows.push(row);
    }
    const sb = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    let inserted = 0;
    for (let i = 0; i < rows.length; i += 1000) {
      const batch = rows.slice(i, i + 1000);
      const { error } = await sb.from("price_history")
        .upsert(batch, { onConflict: "day" });
      if (error) {
        return new Response(
          JSON.stringify({ error: error.message, at: i }),
          { status: 500, headers: { "Content-Type": "application/json" } },
        );
      }
      inserted += batch.length;
    }
    const days = rows.map((r) => r.day as string);
    return new Response(
      JSON.stringify({ ok: true, inserted, first: days[0], last: days.at(-1) }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ error: String(e) }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
