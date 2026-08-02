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
      aria-describedby="auth-modal-description"
      aria-labelledby="auth-modal-title"
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/55 px-4 py-6 backdrop-blur-sm"
      role="dialog"
    >
      <div className="relative w-full max-w-md overflow-hidden rounded-lg border border-white/70 bg-white shadow-2xl">
        <div className="absolute inset-x-0 top-0 h-1 bg-gradient-to-r from-emerald-400 via-sky-400 to-indigo-500" />

        <button
          aria-label="Закрити"
          className="absolute right-4 top-4 grid h-9 w-9 place-items-center rounded-full border border-slate-200 bg-white text-lg font-bold leading-none text-slate-500 shadow-sm transition hover:border-slate-300 hover:bg-slate-50 hover:text-slate-950"
          onClick={onClose}
          type="button"
        >
          x
        </button>

        <div className="px-7 pb-7 pt-8">
          <div className="mb-5 grid h-14 w-14 place-items-center rounded-lg bg-emerald-50 text-2xl font-black text-emerald-700 shadow-inner">
            EO
          </div>

          <div className="pr-10">
            <h2
              className="text-2xl font-bold tracking-normal text-slate-950"
              id="auth-modal-title"
            >
              Увійти до гри
            </h2>
            <p
              className="mt-3 text-sm leading-6 text-slate-600"
              id="auth-modal-description"
            >
              Продовжіть через Google, щоб створювати партії, приєднуватися до
              друзів і зберігати свій прогрес.
            </p>
          </div>

          {error ? (
            <p className="mt-5 rounded-md border border-rose-200 bg-rose-50 px-4 py-3 text-sm font-semibold leading-6 text-rose-800">
              {error}
            </p>
          ) : null}

          <button
            className="mt-6 inline-flex h-12 w-full items-center justify-center gap-3 rounded-md bg-slate-950 px-4 text-sm font-bold text-white shadow-lg shadow-slate-950/15 transition hover:-translate-y-0.5 hover:bg-slate-800 hover:shadow-xl disabled:translate-y-0 disabled:cursor-not-allowed disabled:bg-slate-300 disabled:shadow-none"
            disabled={busy}
            onClick={() => void onSignIn()}
            type="button"
          >
            <span className="grid h-6 w-6 place-items-center rounded-full bg-white text-sm font-black text-slate-950">
              G
            </span>
            {busy ? 'Переходимо до Google...' : 'Увійти через Google'}
          </button>
        </div>
      </div>
    </div>
  );
}

export default AuthModal;
