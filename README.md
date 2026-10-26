# Anatry — science, together

A responsive, forest-green/ivory/gold science research community frontend with a **real Supabase-backed workflow** for authentication, mentor applications, project/team applications, shared team notes, research submissions, founder moderation, reports, and live aggregate statistics.

## IMPORTANT: before opening registration

**This is a deployable application starter, not a fully audited child-safety platform.** Do not invite minors to create accounts until a responsible adult/operator has established a safeguarding policy, guardian consent where legally required, moderation staffing and response processes, privacy notice, terms, retention/deletion procedure, verified mentor identity process, and security testing. Never promise that a site is safe merely because it uses authentication and row-level security.

The public marketing site can go live now with the backend unconfigured. In that state, signup and collaborative actions are **disabled**, and counters display dashes.

## Quick public preview (GitHub Pages)

1. Upload **all** these files/folders to your repository root: `index.html`, `styles.css`, `app.js`, `config.js`, `assets/logo.webp`, `sql/setup.sql` and `README.md`. (The `sql` file isn't required for the public site, but is useful for setup.)
2. Go to GitHub repository **Settings → Pages → Deploy from a branch → main / (root)**.
3. Wait for the Pages link and test in a private/incognito window on desktop and mobile.
4. Do **not** advertise signup, active teams, real publication counts or operational moderation before the backend is configured and tested.

## Set up live accounts, teams, and moderation (Supabase)

1. Create a project at https://supabase.com and enable email confirmation in **Authentication → Providers → Email**. Consider enabling CAPTCHA, appropriate email rate limits, and MFA for founder accounts. Avoid social login until its consent flows are reviewed.
2. In Supabase **SQL Editor**, run `sql/setup.sql` on a new empty project. The schema enables row-level security (RLS) on every table. It creates a founder-only moderation function, a mentor verification check, and aggregated community counts.
3. Go to **Project Settings → API**. Copy **Project URL** and the **publishable/anon key** into `config.js`. **NEVER** use the service role key or a database password in browser code.
4. In **Authentication → URL Configuration**, set the Site URL to your real GitHub Pages URL, and add that URL to the redirect allow list if needed.
5. Sign up for your own account on Anatry, confirm your email, then in Supabase **Authentication → Users**, copy your user UUID.
6. In the SQL Editor, run (replacing the UUID):

   ```sql
   insert into public.admin_users(user_id) values ('YOUR-USER-UUID');
   ```

   **Never add a browser-based founder password or founder signup option.** Admin access must be granted from the database by a trusted operator.
7. Sign out and sign back in. The **Founder Studio** will appear. Verify you can review mentor applications, project proposals, submitted publications, and reports.
8. Create separate test accounts for student and mentor roles. Verify that a student cannot view another student's profile, approve their own mentor application, publish without approval, or read a team room without being approved. Check Supabase logs and run a proper security review before public enrollment.

## What actually works once Supabase is configured

- Email/password registration and login with Supabase Auth, persisted sessions.
- Student and mentor account types. **Mentor status is not verified by account type**; a founder must approve a separate mentor application.
- Verified mentors can propose projects. Founder approves them before they are listed as open.
- Students can apply to open teams. Verified project owners can approve/reject applications.
- Approved team members can post notes visible to that team and founder moderators; no private one-to-one DMs.
- Members can save research drafts and submit for editorial review; only the founder can publish.
- Private concern reports, accessible to the reporter and founder.
- Live aggregate counts for members, published articles, open projects, Bahrain members, and unique voluntarily supplied schools.

## Deliberate limitations

- The editor uses **plain text** instead of allowing arbitrary HTML, to reduce injection risks. Google Docs is linked, not synced or embedded.
- No student private messages, file uploads, external invitations, or automatic mentor matching.
- No automatic Top 10 ranking until there is a fair, moderated ranking policy.
- School counts are aggregate only; school names are not public. The optional school field is sensitive in small communities and may need stronger privacy controls before launch.
- No built-in account deletion workflow, parental consent verification, document scanning, anti-spam throttling, or professional credential verification. Those require additional development and operational processes.
- The app loads Supabase JavaScript from `esm.sh` and Google Fonts from Google. For stricter privacy/security requirements, self-host dependencies, use a build pipeline, add a Content Security Policy and appropriate legal disclosures.
- The app hasn't undergone penetration testing or a complete cross-browser accessibility audit.

## License / attribution

The supplied Anatry logo is from the user's existing project. Do not redistribute the logo independently without permission. No third-party anatomical models are included.