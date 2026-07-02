/* ╔══════════════════════════════════════════════════════════════╗
   ║  KOINONIA — Configuration partagée                            ║
   ║  Clés du projet Supabase "koinonia_mk".                       ║
   ║  index.html ET dashboard.html lisent ce fichier.             ║
   ╚══════════════════════════════════════════════════════════════╝ */
window.KOINONIA = {
  SUPABASE_URL:      "https://mnfekyswsqvhdvgjfqwx.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1uZmVreXN3c3F2aGR2Z2pmcXd4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI1MTQwMTUsImV4cCI6MjA5ODA5MDAxNX0.G_mRp_Oy0HJX4Mg6N4FZ7ujjl5TjL5peJAH8ibJdGRc",
  CHURCH_ID:         "11111111-1111-1111-1111-111111111111",
  CHURCH_NAME:       "Dans Ta Présence Church",
  CITY:              "Kinshasa · RD Congo",
  VAPID_PUBLIC_KEY:  "BF0qOWIELgNYNlMzhSLbSPe62SOoM9HBEeFDEhpS8CLyyVQH5KcxU7R9Hd11GNux-AkOZHImWlIr_JG2bpjzyxs"
};

window.KOINONIA.isConfigured = function () {
  return !this.SUPABASE_URL.includes("VOTRE-PROJET") &&
         typeof window.supabase !== "undefined";
};

window.KOINONIA.client = function () {
  if (this._client) return this._client;
  if (!this.isConfigured()) return null;
  this._client = window.supabase.createClient(this.SUPABASE_URL, this.SUPABASE_ANON_KEY);
  return this._client;
};
