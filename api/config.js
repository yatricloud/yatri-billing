// Vercel Serverless Function: GET /api/config
// Securely provides public environment variables to the web frontend at runtime.
// Secrets such as service_role keys, database passwords, etc. are strictly blocked.

module.exports = (req, res) => {
  // Prevent any caching of configuration
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0');
  res.setHeader('Content-Type', 'application/json');

  const supabaseUrl = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL || '';
  const supabaseAnonKey = process.env.SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '';

  // SECURITY CHECK: Strictly forbid service_role keys from leaking to client
  if (supabaseAnonKey.includes('service_role')) {
    return res.status(500).json({
      error: 'CRITICAL SECURITY VIOLATION: A service_role key was provided in environment variables. ' +
             'Only public anon keys can be exposed to frontend applications.',
    });
  }

  res.status(200).json({
    supabaseUrl,
    supabaseAnonKey,
  });
};
