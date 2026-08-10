# Supabase feedback setup

1. In Supabase, enable **Anonymous Sign-Ins** under Authentication settings.
2. Open the SQL Editor and run both migrations in this order:
   - `migrations/20260810180000_create_feedback.sql`
   - `migrations/20260810190000_require_feedback_approval.sql`
3. In Data API settings, expose `feedback_posts` and `feedback_votes` in the `public` schema.
4. Keep RLS enabled. The migrations grant public read access to published posts and restrict writes and votes to the current anonymous user.

The iOS app uses the publishable key only. Never add a secret or service-role key to the app.

## Neue Beiträge prüfen und freigeben

Der kostenlose Workflow benötigt keinen E-Mail-Dienst:

1. Im Supabase-Dashboard **Table Editor → `feedback_posts`** öffnen.
2. Nach `is_published = false` und `status = under_review` filtern.
3. Titel und Beschreibung prüfen.
4. Bei einem sinnvollen Beitrag `is_published` auf `true` setzen.
5. Für die Roadmap zusätzlich `status` auf `planned` oder `in_progress` setzen.

Nicht freigegebene Beiträge bleiben für andere Nutzer unsichtbar. Eine Admin-Ansicht direkt in der öffentlichen App wird bewusst nicht eingebaut, weil sie ohne separates Admin-Login nicht sicher geschützt werden könnte.
