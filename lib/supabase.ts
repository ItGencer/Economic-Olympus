'use client';

import {
  createClient,
  type SupabaseClient,
  type User,
} from '@supabase/supabase-js';

let browserClient: SupabaseClient | null = null;
const TEST_PLAYER_ID_KEY = 'economic-olympus-test-player-id';
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

function createFallbackUuid() {
  const bytes = Array.from({ length: 16 }, () =>
    Math.floor(Math.random() * 256),
  );

  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  const hex = bytes.map((byte) => byte.toString(16).padStart(2, '0'));

  return [
    hex.slice(0, 4).join(''),
    hex.slice(4, 6).join(''),
    hex.slice(6, 8).join(''),
    hex.slice(8, 10).join(''),
    hex.slice(10, 16).join(''),
  ].join('-');
}

function createTestPlayerId() {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) {
    return crypto.randomUUID();
  }

  return createFallbackUuid();
}

function readTestPlayerId() {
  if (typeof window === 'undefined') {
    return createTestPlayerId();
  }

  const existingId = window.localStorage.getItem(TEST_PLAYER_ID_KEY);

  if (existingId?.trim()) {
    return existingId.trim();
  }

  const nextId = createTestPlayerId();
  window.localStorage.setItem(TEST_PLAYER_ID_KEY, nextId);

  return nextId;
}

export function isAnonymousUser(user: User | null | undefined) {
  return Boolean(user?.is_anonymous || user?.user_metadata?.test_version);
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

function readLocalTestUser(): User {
  const name = readTestPlayerName();

  return {
    app_metadata: {
      provider: 'test',
      providers: ['test'],
    },
    aud: 'authenticated',
    created_at: new Date(0).toISOString(),
    email: undefined,
    id: readTestPlayerId(),
    is_anonymous: true,
    role: 'authenticated',
    updated_at: new Date(0).toISOString(),
    user_metadata: {
      full_name: name,
      name,
      test_version: true,
    },
  } as User;
}

export function readStoredTestUser(): User | null {
  if (typeof window === 'undefined') {
    return null;
  }

  return window.localStorage.getItem(TEST_PLAYER_ID_KEY)
    ? readLocalTestUser()
    : null;
}

export function clearStoredTestUser() {
  if (typeof window === 'undefined') {
    return;
  }

  window.localStorage.removeItem(TEST_PLAYER_ID_KEY);
  window.localStorage.removeItem(TEST_PLAYER_NAME_KEY);
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

  return readLocalTestUser();
}

type PlayableRpcArgs = Record<string, unknown>;
type PlayableRpcError = {
  code?: string;
  details?: string;
  hint?: string;
  message: string;
};

export async function runPlayableRpc<T = unknown>(
  rpcName: string,
  args: PlayableRpcArgs = {},
): Promise<{ data: T | null; error: PlayableRpcError | null }> {
  const supabase = getSupabaseClient();
  const currentUser = await readSessionUser();

  if (currentUser && !isAnonymousUser(currentUser)) {
    const { data, error } = await supabase.rpc(rpcName, args);

    return {
      data: (data ?? null) as T | null,
      error,
    };
  }

  const testUser = currentUser ?? readLocalTestUser();
  const { data, error } = await supabase.rpc('run_test_rpc', {
    p_args: args,
    p_rpc_name: rpcName,
    p_test_user_id: testUser.id,
  });

  return {
    data: (data ?? null) as T | null,
    error,
  };
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

  clearStoredTestUser();
}
