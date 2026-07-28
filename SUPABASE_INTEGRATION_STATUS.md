# Supabase Integration Status

The public Supabase publishable key has been added to `frontend/config.js`.

Still required before the connection can work:

- `SUPABASE_URL`, in the format `https://<project-ref>.supabase.co`
- Run `Guidrent_All_Migrations.sql` in the Supabase SQL Editor
- Configure Authentication Site URL and redirect URLs after the production domain is known

No secret or service-role key has been added to the frontend.
