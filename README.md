# Economic Olympus

## Local start

```bash
npm install
npm run dev
```

## Vercel deploy

In Vercel project settings add these Environment Variables for Production,
Preview, and Development:

```bash
NEXT_PUBLIC_SUPABASE_URL=https://your-project-ref.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-supabase-anon-key
NEXT_PUBLIC_SITE_URL=https://economic-olympus.vercel.app
```

After changing Environment Variables, run Redeploy in Vercel.

## Supabase Auth redirects

In Supabase Dashboard open Authentication -> URL Configuration and set:

```text
Site URL: https://economic-olympus.vercel.app
Redirect URLs:
https://economic-olympus.vercel.app/**
http://localhost:3000/**
```

If Supabase still has `http://localhost:3000` as Site URL, Google login can
finish on localhost even when the app was opened from Vercel.
