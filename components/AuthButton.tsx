'use client';

import Link from 'next/link';

import { useAuth } from '@/components/AuthProvider';

function readUserName(user: ReturnType<typeof useAuth>['user']) {
  if (!user) {
    return '';
  }

  const metadata = user.user_metadata;
  const name = metadata.full_name ?? metadata.name ?? user.email;

  return typeof name === 'string' && name.trim() ? name : 'Користувач';
}

function readAvatarUrl(user: ReturnType<typeof useAuth>['user']) {
  if (!user) {
    return null;
  }

  const avatarUrl = user.user_metadata.avatar_url ?? user.user_metadata.picture;

  return typeof avatarUrl === 'string' && avatarUrl.trim() ? avatarUrl : null;
}

export function AuthButton() {
  const { loading, openAuthModal, signOut, user } = useAuth();
  const userName = readUserName(user);
  const avatarUrl = readAvatarUrl(user);
  const initial = userName.trim().charAt(0).toUpperCase() || 'U';

  if (loading) {
    return (
      <div className="h-10 w-20 rounded-md border border-slate-200 bg-slate-50" />
    );
  }

  if (!user) {
    return (
      <button
        className="inline-flex h-10 items-center justify-center rounded-md border border-slate-300 px-4 text-sm font-semibold text-slate-700 transition hover:border-slate-400 hover:bg-slate-100"
        onClick={openAuthModal}
        type="button"
      >
        Увійти
      </button>
    );
  }

  return (
    <div className="flex items-center gap-2">
      <Link
        className="hidden h-10 items-center justify-center rounded-md border border-slate-300 px-3 text-sm font-semibold text-slate-700 transition hover:border-slate-400 hover:bg-slate-100 sm:inline-flex"
        href="/profile"
      >
        Кабінет
      </Link>
      <Link
        aria-label="Відкрити кабінет"
        className="flex min-w-0 items-center gap-2 rounded-md px-1 py-0.5 transition hover:bg-slate-100"
        href="/profile"
      >
        <span
          aria-hidden="true"
          className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-slate-900 bg-cover bg-center text-sm font-bold text-white"
          style={avatarUrl ? { backgroundImage: `url(${avatarUrl})` } : undefined}
        >
          {avatarUrl ? null : initial}
        </span>
        <span className="hidden max-w-36 truncate text-sm font-semibold text-slate-700 lg:block">
          {userName}
        </span>
      </Link>
      <button
        className="inline-flex h-10 items-center justify-center rounded-md border border-slate-300 px-3 text-sm font-semibold text-slate-700 transition hover:border-slate-400 hover:bg-slate-100"
        onClick={() => void signOut()}
        type="button"
      >
        Вийти
      </button>
    </div>
  );
}

export default AuthButton;
