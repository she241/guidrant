# What remains before Guidrent can go live

Everything that can be prepared without access to your accounts is included. The following items require owner decisions, external accounts, verification or legal approval.

## Required

1. **Final domain** and access to its DNS dashboard. Do not share the registrar password; make DNS changes directly or through a connected deployment tool.
2. **Supabase project** with the two SQL migrations applied.
3. **Public Supabase URL and publishable key** added to `frontend/config.js`.
4. **First administrator account** created and promoted through the SQL instruction in the README.
5. **Hosting project** created and the `frontend` directory deployed.
6. **Production URLs** added to Supabase Auth redirect and site URL settings.
7. **Legal entity and contact details** inserted into every legal/support page.
8. **Ghana legal and data-protection review**, including the final retention schedule and DPC compliance/registration steps.
9. **Permission for listings and photographs**. Current imported examples must remain demos or be replaced by authorised agent/owner submissions or a formal feed.
10. **Real support process** with monitored email, safety escalation, privacy handling and account ownership.
11. **End-to-end testing** using separate seeker, agent and admin accounts.

## Required only when enabling the feature

- Email/SMS/WhatsApp provider credentials for external notifications.
- A paid or free Node host if the optional Express API is enabled.
- Maps/geocoding provider and billing controls if a live interactive map replaces the demo map.
- Payment provider, merchant approval, refunds, reconciliation and financial controls before accepting money.
- Analytics provider and updated consent disclosures if optional analytics are enabled.
- Error-monitoring/status-page provider for public incident visibility.

## Owner decisions still needed

- Legal company name and structure.
- Revenue model: subscriptions, featured listings, lead fees, commissions or no fee at launch.
- Verification evidence required from agents and property owners.
- Listing approval service level and support hours.
- Refund and cancellation rules if payments are added.
- Final launch areas beyond Accra and supported currencies.
