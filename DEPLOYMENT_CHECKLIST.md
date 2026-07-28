# Guidrent deployment checklist

## Business and ownership

- [ ] Legal entity and trade name confirmed
- [ ] Domain owner and renewal method recorded
- [ ] Production Supabase and hosting accounts owned by the business
- [ ] At least two trusted people can recover critical accounts
- [ ] Support, privacy, safety and security emails monitored

## Database and authentication

- [ ] Both SQL migrations applied in order
- [ ] RLS smoke tests executed
- [ ] Email confirmation and password controls enabled
- [ ] Site URL and all redirect URLs configured
- [ ] First administrator created; public signup cannot create admins
- [ ] Separate seeker, agent and admin test accounts created

## Frontend

- [ ] `frontend/config.js` contains correct public values
- [ ] Domain placeholders replaced in legal pages, sitemap and security.txt
- [ ] Mobile, desktop and slow-network testing completed
- [ ] PWA installation and offline fallback tested
- [ ] 404 and expired-session behaviour tested

## Listings and moderation

- [ ] Imported examples remain demos or have written permission
- [ ] Real agents can submit, edit and archive listings
- [ ] Listing photo rights and authority are verified
- [ ] Claim/removal process is staffed
- [ ] Agent verification evidence and badge meaning approved

## Privacy and security

- [ ] Legal pages reviewed and owner details completed
- [ ] DPC compliance/registration work completed
- [ ] Retention and deletion schedule approved
- [ ] Private files cannot be opened publicly
- [ ] Secrets stored only in provider secret managers
- [ ] Backups and restore test completed
- [ ] Incident-response contacts and process approved

## Optional integrations

- [ ] External email/SMS/WhatsApp provider configured and tested
- [ ] Saved-search scheduler configured with a secure cron secret
- [ ] Error monitoring and public status page configured
- [ ] Map/geocoding provider configured with billing limits
- [ ] Payment provider and financial controls approved before accepting funds

## Go-live gate

- [ ] Full end-to-end test passed
- [ ] Legal/business owner signs off
- [ ] Support and moderation are staffed for launch day
- [ ] Rollback procedure and backup confirmed
