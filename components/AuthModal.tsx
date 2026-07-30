'use client';

type AuthModalProps = {
  busy?: boolean;
  error?: string | null;
  open: boolean;
  onClose: () => void;
  onSignIn: () => Promise<void> | void;
};

export function AuthModal({
  busy = false,
  error,
  open,
  onClose,
  onSignIn,
}: AuthModalProps) {
  if (!open) {
    return null;
  }

  return (
    <div
      aria-labelledby="auth-modal-title"
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/60 px-4 py-6"
      role="dialog"
    >
      <div className="w-full max-w-sm rounded-md border border-slate-200 bg-white p-5 shadow-xl">
        <div className="flex items-start justify-between gap-4">
          <div className="min-w-0">
            <h2
              className="text-xl font-bold tracking-normal text-slate-950"
              id="auth-modal-title"
            >
              Увійти в гру
            </h2>
            <p className="mt-2 text-sm leading-6 text-slate-600">
              Авторизація потрібна, щоб Supabase RPC бачили ваш `auth.uid()`.
            </p>
          </div>
          <button
            aria-label="Закрити"
            className="h-8 w-8 shrink-0 rounded-md border border-slate-200 text-lg font-bold leading-none text-slate-500 transition hover:bg-slate-50 hover:text-slate-950"
            onClick={onClose}
            type="button"
          >
            x
          </button>
        </div>

        {error ? (
          <p className="mt-4 rounded-md border border-rose-200 bg-rose-50 px-3 py-2 text-sm font-semibold text-rose-800">
            {error}
          </p>
        ) : null}

        <button
          className="mt-5 inline-flex h-11 w-full items-center justify-center rounded-md bg-slate-950 px-4 text-sm font-semibold text-white transition hover:bg-slate-800 disabled:cursor-not-allowed disabled:bg-slate-300"
          disabled={busy}
          onClick={() => void onSignIn()}
          type="button"
        >
          {busy ? 'Переходимо...' : 'Увійти через Google'}
        </button>
      </div>
    </div>
  );
}

export default AuthModal;
