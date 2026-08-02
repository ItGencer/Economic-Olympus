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
```

After changing Environment Variables, run Redeploy in Vercel.
