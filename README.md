# Guidrent Complete Full-Stack Release

This package is a production-oriented foundation for a Ghana-first property marketplace connecting housing seekers, agents and property managers.

## Included

### Marketplace frontend

- Responsive desktop and mobile property marketplace
- Real public Accra listing examples with source disclosures
- Search, filters, saved homes, comparison and tours
- Seeker, agent and property onboarding page
- Role-aware user dashboard
- Administrator moderation dashboard
- PWA manifest, service worker and offline page
- Privacy-first cookie control and disabled-by-default analytics hook
- Privacy, Terms, Cookies, Safety, Accessibility, Support and Listing Standards pages
- Robots, sitemap, security.txt, redirects and security headers

### Supabase backend

- Email/password authentication
- Seeker, agent and administrator roles
- Agent profiles and private verification files
- Property listings, multiple photos, moderation and source provenance
- Saved homes and shortlist notes
- Saved searches and alert preferences
- Tours and agent availability slots
- Real-time conversations and messages with attachments metadata
- Rental applications and private application documents
- Notifications and user preferences
- Agent reviews and reports
- Imported-listing claims
- Consent records and data-subject requests
- Price history and privacy-friendly daily listing analytics
- Audit logs and Row-Level Security
- Storage policies for public and private files

### Optional Node API

The browser can use Supabase directly under Row-Level Security. The Express API is optional and adds:

- Request validation
- Central rate limiting and security headers
- Structured request IDs and logs
- Readiness and health endpoints
- Aggregated user-data export
- Administrator endpoints using a server-only secret key
- Easier integration with webhooks and external notification providers

### Deployment and operations

- Cloudflare Pages configuration
- Netlify and Vercel configuration
- Docker and Render examples
- GitHub Actions checks
- Operations, backups, incident response, listing-data policy and test documentation
- A clear remaining-before-launch checklist

## Quick setup

### 1. Create Supabase

Create a new project and apply, in order:

1. `supabase/migrations/202607270001_guidrent_core.sql`
2. `supabase/migrations/202607270002_guidrent_production.sql`
3. Optional: `supabase/seed.sql`

The root file `Guidrent_All_Migrations.sql` combines both migrations for SQL Editor use.

### 2. Configure the frontend

Edit `frontend/config.js` with only public values:

```js
window.GUIDRENT_CONFIG = {
  SUPABASE_URL: 'https://YOUR_PROJECT.supabase.co',
  SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_...',
  API_URL: '',
  SITE_URL: 'https://www.yourdomain.com',
  SUPPORT_EMAIL: 'support@yourdomain.com',
  PRIVACY_EMAIL: 'privacy@yourdomain.com',
  SAFETY_EMAIL: 'safety@yourdomain.com',
  SUPPORT_WHATSAPP: '',
  ENABLE_ANALYTICS: false
};
```

Never place a Supabase secret or service-role key in browser files.

### 3. Create the first administrator

Register normally, then run this with the correct email:

```sql
update public.profiles p
set role = 'admin'
from auth.users u
where p.id = u.id
  and lower(u.email) = lower('admin@example.com');
```

### 4. Run locally with Cloudflare Workers

Install the pinned Wrangler version and start the local Workers Static Assets
server:

```bash
npm install
npm run dev
```

Open:

- Marketplace: `http://localhost:8787`
- Account setup: `http://localhost:8787/account.html`
- Dashboard: `http://localhost:8787/dashboard.html`
- Admin centre: `http://localhost:8787/admin.html`

The project uses an assets-only Worker. Supabase remains the system of record
for authentication, Postgres data, storage, messaging and tour requests.

### 5. Deploy the frontend to Cloudflare

Confirm which Cloudflare account Wrangler is using, validate the upload without
publishing, and then deploy:

```bash
npm run cf:whoami
npm run deploy:dry-run
npm run deploy
```

The deployment configuration is in `wrangler.jsonc`. Unknown routes return the
project's `frontend/404.html` with a 404 status. No secret keys are stored in
Wrangler or in browser files.

### 6. Optional API

```bash
cd api
cp .env.example .env
npm install
npm run check
npm test
npm run dev
```

Set `API_URL` in the frontend only after the API is deployed with HTTPS and the correct CORS origin.

### 7. Deploy Edge Functions

```bash
supabase functions deploy notify-tour
supabase functions deploy moderate-listing
supabase functions deploy notify-message
supabase functions deploy notify-application
supabase functions deploy saved-search-alerts

supabase secrets set NOTIFICATION_WEBHOOK_URL=https://YOUR_OPTIONAL_WEBHOOK
supabase secrets set CRON_SECRET=GENERATE_A_LONG_RANDOM_SECRET
```

The webhook, external email/SMS/WhatsApp delivery and scheduled invocation are optional integrations and are not active until configured.

## Main API routes

| Method | Route | Purpose |
|---|---|---|
| GET | `/health` | Service health |
| GET | `/ready` | Database readiness |
| GET/POST/PATCH | `/api/properties` | Public search and agent listings |
| GET/POST/PATCH | `/api/availability` | Agent tour slots |
| GET/POST/DELETE | `/api/favorites` | Saved homes |
| GET/POST/PATCH | `/api/tours` | Property tours |
| GET/POST | `/api/messages/...` | Conversations and messages |
| GET/POST/PATCH/DELETE | `/api/saved-searches` | Search alerts |
| GET/POST/PATCH | `/api/applications` | Rental applications |
| GET/PATCH/PUT | `/api/notifications` | Notifications and preferences |
| GET/POST | `/api/privacy` | Data export, consent and privacy requests |
| GET/POST | `/api/claims` | Imported-listing claims |
| POST/GET | `/api/analytics` | Listing events and owner analytics |
| GET/PATCH | `/api/admin` | Moderation and privacy queues |

## Security model

- Public users see only published properties and allowed public profile fields.
- Users can access only their own private profile, saved data and privacy records.
- Conversation and tour access is limited to participants.
- Agents access only properties, applications and analytics connected to them.
- Identity and application documents are stored in private buckets.
- Administrator-only moderation fields are protected by database functions and RLS.
- The browser publishable key is expected to be public; database security depends on RLS.
- The server secret key is server-only and must be rotated if exposed.

## Final launch status

The core software foundation is prepared. Account-owned tasks and legal/business decisions remain. Read:

- `REMAINING_BEFORE_GO_LIVE.md`
- `DEPLOYMENT_CHECKLIST.md`
- `docs/LEGAL_AND_COMPLIANCE.md`
- `docs/TEST_PLAN.md`

Do not commercially launch imported listings or accept money until permissions, support, legal review, verification rules and payment controls are complete.
