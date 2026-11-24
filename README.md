# Reeta Salon

A static salon site with a public booking portal and staff tools.

## Features

- Public service menu, walk-in token and appointment requests, and private-code status lookup
- Supabase-backed service catalog and customer requests, with staff authentication and row-level access controls
- Staff-only online request queue with status updates
- Legacy dashboard, CRM, appointments, stylist list, and reports stored in that browser's local storage
- Responsive layout, dark/light themes, and local JSON backup for browser-stored data

Only the service catalog and online customer requests are shared through Supabase. Other legacy dashboard records remain device-local and are not synchronized between staff members. Do not treat a browser backup as a backup of Supabase requests.

## Free hosted URL

`https://rajasuna.github.io/Reeta-salon/`

GitHub Pages serves the static site directly from this public repository at no hosting cost.

### Enable GitHub Pages

1. Open the repository on GitHub and go to **Settings > Pages**.
2. Under **Build and deployment**, select **Deploy from a branch**.
3. Select the `main` branch and `/(root)` as the folder, then save.
4. Wait for GitHub Pages to publish the site.

No custom domain, DNS change, or paid hosting is required for the free `.github.io` address.

## Configure Supabase booking

The site does not submit bookings or tokens to local storage. Until Supabase is configured, the public booking controls stay unavailable and do not show a false success.

1. Create a Supabase project and open its **SQL Editor**.
2. Run [`supabase/schema.sql`](supabase/schema.sql) to create the catalog, request tables, staff authorization policy, and public RPCs.
3. In Supabase Authentication, create/invite each staff user and disable public sign-ups if staff accounts should be invitation-only.
4. Add each staff user's Auth UUID to `public.staff_profiles` in the SQL Editor:

   ```sql
   insert into public.staff_profiles (user_id, display_name)
   values ('AUTH_USER_UUID', 'Staff display name');
   ```

5. In **Project Settings > API**, copy the project URL and the public anon/publishable key into `supabase-config.js`:

   ```js
   window.REETA_SUPABASE_CONFIG = {
     url: "https://YOUR_PROJECT_REF.supabase.co",
     anonKey: "YOUR_PUBLIC_ANON_OR_PUBLISHABLE_KEY"
   };
   ```

   This file is downloaded by every visitor. Only use the public anon/publishable key; **never put a service-role key or other secret in the site**. The public key is safe only while the SQL grants, row-level security policies, and RPC permissions remain in place.

6. Sign in through **Staff Sign In** and add the salon's real service names, prices, and durations. Online booking stays unavailable until active services exist.
7. Publish the repository changes through the configured Pages branch. No Supabase account, project, secret, or live setting is created by these repository changes.

The public can submit a request through a validated RPC and can check only its status using the private access code shown on the receipt. The database stores a hash of that code. Customer names and phone numbers are only returned to authorized staff; the public status RPC does not expose them. The public submission RPC is internet-accessible, so add server-side rate limiting or a challenge before relying on it for a high-traffic launch.

## Google Search and Business Profile

The site includes a description, canonical URL, social sharing metadata, `robots.txt`, and `sitemap.xml`. These help crawlers discover the site but do not guarantee indexing or search placement.

1. Open [Google Search Console](https://search.google.com/search-console), add the URL-prefix property `https://rajasuna.github.io/Reeta-salon/`, and complete Google's ownership verification. For HTML-file verification, place Google's downloaded file at the repository root and publish it; alternatively, add the exact verification meta tag Google provides.
2. In Search Console, submit `https://rajasuna.github.io/Reeta-salon/sitemap.xml`. You can also use URL Inspection to request indexing after the live site is available.
3. If the salon is eligible, create or claim a Google Business Profile and enter only accurate, owner-verified business information. Use the real business name, category, address or service area, hours, phone, and website; do not infer missing details from this repository. A profile is generally for businesses that meet customers in person, not online-only businesses.

Google account ownership verification and any Business Profile verification must be completed by the business owner. Neither indexing nor a particular ranking is guaranteed.
