'use client';

import {
  createClient,
  type SupabaseClient,
  type User,
} from '@supabase/supabase-js';

let browserClient: SupabaseClient | null = null;
const TEST_PLAYER_NAME_KEY = 'economic-olympus-test-player-name';

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

function normalizeSiteUrl(value: string | undefined) {
  if (!value) {
    return undefined;
  }

  try {
    const url = new URL(value);

    return url.origin;
  } catch {
    return undefined;
  }
}

function readOAuthRedirectTo() {
  const configuredSiteUrl = normalizeSiteUrl(
    readPublicEnvValue(process.env.NEXT_PUBLIC_SITE_URL),
  );

  if (configuredSiteUrl) {
    return configuredSiteUrl;
  }

  return typeof window === 'undefined' ? undefined : window.location.origin;
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

async function readSessionUser(): Promise<User | null> {
  const supabase = getSupabaseClient();
  const { data: sessionData, error: sessionError } =
    await supabase.auth.getSession();

  if (sessionError) {
    throw sessionError;
  }

  return sessionData.session?.user ?? null;
}

function createTestPlayerName() {
  const suffix =
    typeof crypto !== 'undefined' && 'randomUUID' in crypto
      ? crypto.randomUUID().slice(0, 4).toUpperCase()
      : Math.random().toString(36).slice(2, 6).toUpperCase();

  return `Тестовий гравець ${suffix}`;
}

export function isAnonymousUser(user: User | null | undefined) {
  return Boolean(user?.is_anonymous);
}

export function readPlayableUserName(user: User | null | undefined) {
  if (!user) {
    return 'Гравець';
  }

  const name =
    user.user_metadata.full_name ?? user.user_metadata.name ?? user.email;

  if (typeof name === 'string' && name.trim()) {
    return name.trim();
  }

  return isAnonymousUser(user) ? 'Тестовий гравець' : 'Гравець';
}

function readTestPlayerName() {
  if (typeof window === 'undefined') {
    return 'Тестовий гравець';
  }

  const existingName = window.localStorage.getItem(TEST_PLAYER_NAME_KEY);

  if (existingName?.trim()) {
    return existingName.trim();
  }

  const nextName = createTestPlayerName();
  window.localStorage.setItem(TEST_PLAYER_NAME_KEY, nextName);

  return nextName;
}

export async function requireAuthenticatedUser(): Promise<User> {
  const user = await readSessionUser();

  if (user) {
    return user;
  }

  throw new Error('Потрібно увійти через Google.');
}

export async function ensurePlayableUser(): Promise<User> {
  const currentUser = await readSessionUser();

  if (currentUser) {
    return currentUser;
  }

  const supabase = getSupabaseClient();
  const displayName = readTestPlayerName();
  const { data, error } = await supabase.auth.signInAnonymously({
    options: {
      data: {
        full_name: displayName,
        name: displayName,
        test_version: true,
      },
    },
  });

  if (error) {
    throw new Error(
      `${error.message} У Supabase Auth потрібно увімкнути Anonymous sign-ins для тестової версії гри.`,
    );
  }

  const user = data.user ?? data.session?.user ?? null;

  if (!user) {
    throw new Error('Не вдалося створити тестову сесію гравця.');
  }

  return user;
}

export async function signInWithGoogle(): Promise<void> {
  const supabase = getSupabaseClient();
  const redirectTo = readOAuthRedirectTo();
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
