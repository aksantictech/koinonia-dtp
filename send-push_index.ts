// KOINONIA — Fonction Edge "send-push" (v2)
// Envoie une notification push à tous les abonnés (table push_subscriptions).
//
// ⚠️ IMPORTANT : sur les projets migrés au nouveau système de clés Supabase,
// il FAUT désactiver "Verify JWT" pour cette fonction (Dashboard → Edge
// Functions → send-push → Details → Verify JWT = OFF). L'authentification est
// gérée ici dans le code (on valide l'utilisateur et son rôle).
//
// Secrets requis : VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT
// (SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY sont fournis automatiquement)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // --- Authentification de l'appelant (à la place de verify_jwt) ---
    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!token) return json({ ok: false, error: "Jeton manquant" }, 401);

    const { data: { user }, error: uerr } = await admin.auth.getUser(token);
    if (uerr || !user) return json({ ok: false, error: "Utilisateur non authentifié" }, 401);

    const { data: prof } = await admin.from("profiles").select("role").eq("id", user.id).single();
    const role = prof?.role;
    if (!["pasteur_titulaire", "pasteur_site", "admin", "saisie"].includes(role)) {
      return json({ ok: false, error: "Rôle non autorisé : " + role }, 403);
    }

    // --- VAPID ---
    webpush.setVapidDetails(
      Deno.env.get("VAPID_SUBJECT") ?? "mailto:contact@example.org",
      Deno.env.get("VAPID_PUBLIC_KEY")!,
      Deno.env.get("VAPID_PRIVATE_KEY")!,
    );

    const { title, body, kind, url } = await req.json();

    const { data: subs, error: serr } = await admin
      .from("push_subscriptions")
      .select("id, endpoint, p256dh, auth");
    if (serr) throw serr;

    const payload = JSON.stringify({
      title: title ?? "Dans Ta Présence Church",
      body: body ?? "",
      kind: kind ?? "",
      url: url ?? "/index.html",
    });

    let sent = 0, removed = 0;
    for (const s of subs ?? []) {
      try {
        await webpush.sendNotification(
          { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
          payload,
        );
        sent++;
      } catch (e) {
        const code = (e as { statusCode?: number })?.statusCode;
        if (code === 404 || code === 410) {
          await admin.from("push_subscriptions").delete().eq("id", s.id);
          removed++;
        }
      }
    }

    return json({ ok: true, sent, removed, subscribers: (subs ?? []).length });
  } catch (e) {
    return json({ ok: false, error: String(e) }, 500);
  }
});
