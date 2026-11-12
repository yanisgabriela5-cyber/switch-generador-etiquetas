/* Conexión con la base compartida (Supabase).
   Se copian de Supabase → Project Settings → API:
     · Project URL        → url
     · anon public key    → claveAnon
   La clave "anon" está hecha para ir en la página: la base solo acepta las funciones et_* del esquema. */
window.CONFIG_ETIQUETAS = {
  url: '',
  claveAnon: ''
};
