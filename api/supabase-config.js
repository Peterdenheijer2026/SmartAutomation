module.exports = async function handler(req, res) {
  const url = process.env.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY;

  if (!url || !anonKey) {
    return res.status(500).json({
      error:
        "Missing SUPABASE_URL or SUPABASE_ANON_KEY in Vercel Environment Variables.",
    });
  }

  return res.status(200).json({ url, anonKey });
};

