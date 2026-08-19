'use client';

type AuthModalProps = {
  busy?: boolean;
  error?: string | null;
  open: boolean;
  onClose: () => void;
  onSignIn: () => Promise<void> | void;
  onStartTestSession?: () => Promise<void> | void;
};

export function AuthModal({
  busy = false,
  error,
  open,
  onClose,
  onSignIn,
  onStartTestSession,
}: AuthModalProps) {
  if (!open) {
    return null;
  }

  return (
    <div
      aria-describedby="auth-modal-description"
      aria-labelledby="auth-modal-title"
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center bg-[#070710]/65 px-4 py-6 backdrop-blur-md"
      role="dialog"
    >
      <div className="neo-panel neo-modal-panel relative w-full max-w-md overflow-hidden rounded-[20px] border border-violet-300/35 bg-[#181824] shadow-2xl">
        <div className="absolute inset-x-0 top-0 h-1 bg-gradient-to-r from-violet-500 via-fuchsia-300 to-violet-700" />
        <div className="pointer-events-none absolute -right-20 -top-24 h-48 w-48 rounded-full bg-violet-500/25 blur-3xl" />

        <button
          aria-label="Закрити"
          className="neo-button absolute right-4 top-4 grid h-9 w-9 place-items-center rounded-full border border-violet-300/30 bg-[#12121a]/80 text-lg font-bold leading-none text-slate-300 shadow-sm transition hover:border-fuchsia-300/70 hover:text-white"
          onClick={onClose}
          type="button"
        >
          x
        </button>

        <div className="px-7 pb-7 pt-8">
          <div className="mb-5 grid h-14 w-14 place-items-center rounded-[18px] border border-violet-300/30 bg-violet-500/15 text-2xl font-black text-fuchsia-200 shadow-[inset_6px_6px_14px_rgba(2,2,8,0.45),inset_-6px_-6px_14px_rgba(192,132,252,0.12)]">
            EO
          </div>

          <div className="pr-10">
            <h2
              className="neo-heading text-2xl font-bold tracking-normal text-violet-50"
              id="auth-modal-title"
            >
              Увійти до гри
            </h2>
            <p
              className="mt-3 text-sm leading-6 text-slate-300"
              id="auth-modal-description"
            >
              Продовжіть через Google, щоб створювати партії, приєднуватися до
              друзів і зберігати свій прогрес.
            </p>
          </div>

          {error ? (
            <p className="mt-5 rounded-[16px] border border-rose-300/35 bg-rose-500/12 px-4 py-3 text-sm font-semibold leading-6 text-rose-100">
              {error}
            </p>
          ) : null}

          <button
            className="neo-button mt-6 inline-flex h-12 w-full items-center justify-center gap-3 rounded-[18px] bg-slate-950 px-4 text-sm font-bold text-white shadow-lg shadow-slate-950/15 transition hover:-translate-y-0.5 hover:bg-slate-800 hover:shadow-xl disabled:translate-y-0 disabled:cursor-not-allowed disabled:bg-slate-300 disabled:shadow-none"
            disabled={busy}
            onClick={() => void onSignIn()}
            type="button"
          >
            <span className="grid h-6 w-6 place-items-center rounded-full bg-white text-sm font-black text-violet-700">
              G
            </span>
            {busy ? 'Переходимо до Google...' : 'Увійти через Google'}
          </button>

          {onStartTestSession ? (
            <button
              className="mt-3 inline-flex h-12 w-full items-center justify-center rounded-[18px] border border-amber-300/35 bg-amber-300/10 px-4 text-sm font-black text-amber-100 transition hover:border-amber-200 hover:bg-amber-300/15 disabled:cursor-not-allowed disabled:opacity-60"
              disabled={busy}
              onClick={() => void onStartTestSession()}
              type="button"
            >
              Тестова версія гри без Google
            </button>
          ) : null}
        </div>
      </div>
    </div>
  );
}

export default AuthModal;
