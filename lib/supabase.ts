'use client';

import {
  createClient,
  type SupabaseClient,
  type User,
} from '@supabase/supabase-js';

let browserClient: SupabaseClient | null = null;

export const SUPABASE_ENV_KEYS = [
  'NEXT_PUBLIC_SUPABASE_URL',
  'NEXT_PUBLIC_SUPABASE_ANON_KEY',
] as const;

export const SUPABASE_CONFIG_ERROR_MESSAGE =
  'Missing NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_ANON_KEY. Add them in Vercel Environment Variables and redeploy.';

export type SupabaseConfigStatus = {
  configured: boolean;
  missingKeys: string[];
  supabaseAnonKey?: string;
  supabaseUrl?: string;
};

function readPublicEnvValue(value: string | undefined) {
  return typeof value === 'string' && value.trim() ? value.trim() : undefined;
}

export function getSupabaseConfigStatus(): SupabaseConfigStatus {
  const supabaseUrl = readPublicEnvValue(process.env.NEXT_PUBLIC_SUPABASE_URL);
  const supabaseAnonKey = readPublicEnvValue(
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  );
  const missingKeys = [
    supabaseUrl ? null : 'NEXT_PUBLIC_SUPABASE_URL',
    supabaseAnonKey ? null : 'NEXT_PUBLIC_SUPABASE_ANON_KEY',
  ].filter((key): key is string => Boolean(key));

  return {
    configured: missingKeys.length === 0,
    missingKeys,
    supabaseAnonKey,
    supabaseUrl,
  };
}

export function getSupabaseSetupErrorMessage() {
  const { missingKeys } = getSupabaseConfigStatus();
  const missing = missingKeys.length ? ` Missing: ${missingKeys.join(', ')}.` : '';

  return `${SUPABASE_CONFIG_ERROR_MESSAGE}${missing}`;
}

export function isSupabaseConfigured() {
  return getSupabaseConfigStatus().configured;
}

function readSupabaseEnv() {
  const { configured, supabaseUrl, supabaseAnonKey } =
    getSupabaseConfigStatus();

  if (!configured || !supabaseUrl || !supabaseAnonKey) {
    throw new Error(getSupabaseSetupErrorMessage());
  }

  return { supabaseUrl, supabaseAnonKey };
}

export function getSupabaseClient(): SupabaseClient {
  if (browserClient) {
    return browserClient;
  }

  const { supabaseUrl, supabaseAnonKey } = readSupabaseEnv();

  browserClient = createClient(supabaseUrl, supabaseAnonKey, {
    auth: {
      autoRefreshToken: true,
      detectSessionInUrl: true,
      persistSession: true,
    },
  });

  return browserClient;
}

export async function requireAuthenticatedUser(): Promise<User> {
  const supabase = getSupabaseClient();
  const { data: sessionData, error: sessionError } =
    await supabase.auth.getSession();

  if (sessionError) {
    throw sessionError;
  }

  if (sessionData.session?.user) {
    return sessionData.session.user;
  }

  throw new Error('Потрібно увійти через Google.');
}

export async function signInWithGoogle(): Promise<void> {
  const supabase = getSupabaseClient();
  const redirectTo =
    typeof window === 'undefined' ? undefined : window.location.href;
  const { error } = await supabase.auth.signInWithOAuth({
    options: redirectTo ? { redirectTo } : undefined,
    provider: 'google',
  });

  if (error) {
    throw error;
  }
}

export async function signOut(): Promise<void> {
  const supabase = getSupabaseClient();
  const { error } = await supabase.auth.signOut();

  if (error) {
    throw error;
  }
}
