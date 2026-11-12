# Generador de Etiquetas — Switch Soft

Diseñador de etiquetas con generación de SKU, en línea. Todos los que abren el generador ven el mismo archivo (Excel/CSV) y los mismos códigos, actualizados cada pocos segundos, y los SKU nuevos nunca se repiten aunque varias personas los generen al mismo tiempo.

## Qué se comparte en línea

- **El archivo de datos.** Cuando alguien sube un Excel o CSV, pasa a ser el archivo de todos. Si ya había uno, la página pregunta antes de reemplazarlo.
- **Los cambios.** SKU generados o escritos a mano, precios, nombres y artículos nuevos llegan a los demás en unos 2–3 segundos.
- **Los números de SKU.** La base reparte los números por prefijo (SG, HP…), así dos personas nunca reciben el mismo código. Puede haber saltos en la numeración (por ejemplo, de SG00009 a SG00028): es normal, porque cada equipo aparta un bloque de números a la vez.
- **Las plantillas de etiqueta.** Al guardar una plantilla, queda disponible para todos.
- **La impresión remota.** Desde el celular se marcan variantes y se usa **Enviar a la PC**. La computadora con la impresora las recibe si tiene abierto el generador con **Activar como receptor** (sección *Impresión remota*). Ya no hace falta `servidor_impresion.py` ni estar en la misma red WiFi.

Sin internet, la página sigue funcionando sola en ese equipo y envía los cambios cuando vuelve la conexión.

## Puesta en marcha (una sola vez)

### 1. Base de datos en Supabase
1. Crea un proyecto gratis en [supabase.com](https://supabase.com).
2. Abre **SQL Editor**, pega todo el contenido de [`supabase/esquema.sql`](supabase/esquema.sql) y presiona **Run**.
3. En **Project Settings → API** copia la **Project URL** y la clave **anon public**.

### 2. Conectar la página
Edita [`config.js`](config.js) y pega los dos valores:

```js
window.CONFIG_ETIQUETAS = {
  url: 'https://xxxxxxxx.supabase.co',
  claveAnon: 'eyJhbGciOi...'
};
```

### 3. Publicar con GitHub Pages
En el repositorio: **Settings → Pages → Build and deployment → Deploy from a branch**, rama `main`, carpeta `/ (root)`. En uno o dos minutos el generador queda en:

`https://<usuario>.github.io/switch-generador-etiquetas/`

Ese es el enlace para compartir con el personal.

## Archivos

| Archivo | Para qué sirve |
|---|---|
| `index.html` | El generador completo (diseño, SKU, impresión). |
| `config.js` | Dirección y clave de la base en línea. |
| `supabase/esquema.sql` | Tablas y funciones de la base. Se puede volver a ejecutar sin perder datos. |

## Seguridad

La clave *anon* va en la página a propósito: la base tiene las tablas cerradas y solo acepta las funciones `et_*` del esquema. Aun así, **cualquiera que tenga el enlace puede ver y cambiar el archivo compartido**, así que el enlace debe quedarse dentro del equipo. Si en algún momento hace falta controlar quién entra, se puede agregar inicio de sesión con Supabase Auth.

## Límites del plan gratis de Supabase

Alcanza de sobra para una tienda: 500 MB de base de datos y uso ilimitado de la API. Si el proyecto pasa una semana sin uso, Supabase lo pausa; se reactiva desde el panel con un clic.
