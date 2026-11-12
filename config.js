/* Conexión con la base compartida (Supabase).
   Se copian de Supabase → Project Settings → API:
     · Project URL        → url
     · Publishable key (sb_publishable_…) o la antigua anon public (eyJ…) → claveAnon
   La clave "anon" está hecha para ir en la página: la base solo acepta las funciones et_* del esquema. */
window.CONFIG_ETIQUETAS = {
  url: 'https://voxennbakcreqvrrcprd.supabase.co',
  claveAnon: ''
};
