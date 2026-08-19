'use client';

import {
  createContext,
  type ReactNode,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from 'react';
import type { User } from '@supabase/supabase-js';

import AuthModal from '@/components/AuthModal';
import {
  ensurePlayableUser,
  getSupabaseConfigStatus,
  getSupabaseClient,
  getSupabaseSetupErrorMessage,
  signInWithGoogle,
  signOut as signOutFromSupabase,
} from '@/lib/supabase';

type AuthContextValue = {
  closeAuthModal: () => void;
  loading: boolean;
  openAuthModal: () => void;
  refreshUser: () => Promise<User | null>;
  signIn: () => Promise<void>;
  startTestSession: () => Promise<void>;
  signOut: () => Promise<void>;
  user: User | null;
};

const AuthContext = createContext<AuthContextValue | null>(null);

function readErrorMessage(error: unknown) {
  if (error instanceof Error) {
    return error.message;
  }

  if (typeof error === 'object' && error && 'message' in error) {
    return String(error.message);
  }

  return 'Невідома помилка авторизації';
}

function SupabaseEnvNotice({ missingKeys }: { missingKeys: string[] }) {
  if (!missingKeys.length) {
    return null;
  }

  return (
    <div className="border-b border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-950">
      <div className="mx-auto max-w-7xl">
        <span className="font-bold">Supabase не налаштовано.</span>{' '}
        Додайте у Vercel Environment Variables:{' '}
        <span className="break-all font-mono font-semibold">
          {missingKeys.join(', ')}
        </span>,
        потім зробіть Redeploy.
      </div>
    </div>
  );
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const supabaseConfig = useMemo(() => getSupabaseConfigStatus(), []);
  const supabaseSetupError = useMemo(() => getSupabaseSetupErrorMessage(), []);
  const [authError, setAuthError] = useState<string | null>(null);
  const [authModalOpen, setAuthModalOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [user, setUser] = useState<User | null>(null);

  const refreshUser = useCallback(async () => {
    if (!supabaseConfig.configured) {
      setAuthError(supabaseSetupError);
      setUser(null);
      setLoading(false);
      return null;
    }

    const supabase = getSupabaseClient();

    setLoading(true);

    try {
      const { data, error } = await supabase.auth.getSession();

      if (error) {
        setAuthError(error.message);
        setUser(null);
        return null;
      }

      const nextUser = data.session?.user ?? null;
      setUser(nextUser);

      if (nextUser) {
        setAuthError(null);
        setAuthModalOpen(false);
      }

      return nextUser;
    } finally {
      setLoading(false);
    }
  }, [supabaseConfig.configured, supabaseSetupError]);

  useEffect(() => {
    if (!supabaseConfig.configured) {
      setAuthError(supabaseSetupError);
      setUser(null);
      setLoading(false);
      return;
    }

    const supabase = getSupabaseClient();
    let mounted = true;

    supabase.auth
      .getSession()
      .then(({ data, error }) => {
        if (!mounted) {
          return;
        }

        if (error) {
          setAuthError(error.message);
        }

        setUser(data.session?.user ?? null);
      })
      .finally(() => {
        if (mounted) {
          setLoading(false);
        }
      });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
      setLoading(false);
      setBusy(false);

      if (session?.user) {
        setAuthError(null);
        setAuthModalOpen(false);
      }
    });

    return () => {
      mounted = false;
      subscription.unsubscribe();
    };
  }, [supabaseConfig.configured, supabaseSetupError]);

  const openAuthModal = useCallback(() => {
    setAuthError(supabaseConfig.configured ? null : supabaseSetupError);
    setAuthModalOpen(true);
  }, [supabaseConfig.configured, supabaseSetupError]);

  const closeAuthModal = useCallback(() => {
    if (!busy) {
      setAuthModalOpen(false);
    }
  }, [busy]);

  const signIn = useCallback(async () => {
    if (!supabaseConfig.configured) {
      setAuthError(supabaseSetupError);
      setAuthModalOpen(true);
      return;
    }

    setBusy(true);
    setAuthError(null);

    try {
      await signInWithGoogle();
    } catch (error) {
      setAuthError(readErrorMessage(error));
      setBusy(false);
    }
  }, [supabaseConfig.configured, supabaseSetupError]);

  const startTestSession = useCallback(async () => {
    if (!supabaseConfig.configured) {
      setAuthError(supabaseSetupError);
      setAuthModalOpen(true);
      return;
    }

    setBusy(true);
    setAuthError(null);

    try {
      const testUser = await ensurePlayableUser();
      setUser(testUser);
      setAuthModalOpen(false);
    } catch (error) {
      setAuthError(readErrorMessage(error));
      setAuthModalOpen(true);
    } finally {
      setBusy(false);
    }
  }, [supabaseConfig.configured, supabaseSetupError]);

  const signOut = useCallback(async () => {
    if (!supabaseConfig.configured) {
      setAuthError(null);
      setUser(null);
      return;
    }

    setBusy(true);
    setAuthError(null);

    try {
      await signOutFromSupabase();
      setUser(null);
    } catch (error) {
      setAuthError(readErrorMessage(error));
      setAuthModalOpen(true);
    } finally {
      setBusy(false);
    }
  }, [supabaseConfig.configured]);

  const value = useMemo<AuthContextValue>(
    () => ({
      closeAuthModal,
      loading,
      openAuthModal,
      refreshUser,
      signIn,
      startTestSession,
      signOut,
      user,
    }),
    [
      closeAuthModal,
      loading,
      openAuthModal,
      refreshUser,
      signIn,
      startTestSession,
      signOut,
      user,
    ],
  );

  return (
    <AuthContext.Provider value={value}>
      <SupabaseEnvNotice missingKeys={supabaseConfig.missingKeys} />
      {children}
      <AuthModal
        busy={busy}
        error={authError}
        onClose={closeAuthModal}
        onSignIn={signIn}
        onStartTestSession={startTestSession}
        open={authModalOpen}
      />
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);

  if (!context) {
    throw new Error('useAuth must be used inside AuthProvider.');
  }

  return context;
}
