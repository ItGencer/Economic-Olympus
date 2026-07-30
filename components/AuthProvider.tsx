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
  getSupabaseClient,
  signInWithGoogle,
  signOut as signOutFromSupabase,
} from '@/lib/supabase';

type AuthContextValue = {
  closeAuthModal: () => void;
  loading: boolean;
  openAuthModal: () => void;
  refreshUser: () => Promise<User | null>;
  signIn: () => Promise<void>;
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

export function AuthProvider({ children }: { children: ReactNode }) {
  const [authError, setAuthError] = useState<string | null>(null);
  const [authModalOpen, setAuthModalOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [user, setUser] = useState<User | null>(null);

  const refreshUser = useCallback(async () => {
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
  }, []);

  useEffect(() => {
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
  }, []);

  const openAuthModal = useCallback(() => {
    setAuthError(null);
    setAuthModalOpen(true);
  }, []);

  const closeAuthModal = useCallback(() => {
    if (!busy) {
      setAuthModalOpen(false);
    }
  }, [busy]);

  const signIn = useCallback(async () => {
    setBusy(true);
    setAuthError(null);

    try {
      await signInWithGoogle();
    } catch (error) {
      setAuthError(readErrorMessage(error));
      setBusy(false);
    }
  }, []);

  const signOut = useCallback(async () => {
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
  }, []);

  const value = useMemo<AuthContextValue>(
    () => ({
      closeAuthModal,
      loading,
      openAuthModal,
      refreshUser,
      signIn,
      signOut,
      user,
    }),
    [closeAuthModal, loading, openAuthModal, refreshUser, signIn, signOut, user],
  );

  return (
    <AuthContext.Provider value={value}>
      {children}
      <AuthModal
        busy={busy}
        error={authError}
        onClose={closeAuthModal}
        onSignIn={signIn}
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
