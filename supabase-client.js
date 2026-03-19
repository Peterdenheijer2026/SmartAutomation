async function getSupabaseConfig() {
  const res = await fetch("/api/supabase-config", { method: "GET" });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(
      `Kon SUPABASE-config niet ophalen (HTTP ${res.status}). ${text}`.trim()
    );
  }
  return res.json();
}

async function initSupabase() {
  // supabase global comes from the CDN script in the HTML pages
  if (!window.supabase || !window.supabase.createClient) {
    throw new Error("Supabase CDN script niet gevonden.");
  }

  const { url, anonKey } = await getSupabaseConfig();
  return window.supabase.createClient(url, anonKey);
}

function formatMoneyEURFromCents(cents) {
  const n = Number(cents || 0);
  return (n / 100).toLocaleString("nl-NL", {
    style: "currency",
    currency: "EUR",
  });
}

