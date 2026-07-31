'use client';

import type { User } from '@supabase/supabase-js';
import Link from 'next/link';
import { FormEvent, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';

import AuthButton from '@/components/AuthButton';
import { useAuth } from '@/components/AuthProvider';
import { getSupabaseClient } from '@/lib/supabase';

type LobbyRpcResult = {
  game_id: string;
  join_code: string;
  player_id?: string;
};

const facts = [
  { label: 'Гравці', value: '2-6' },
  { label: 'Старт', value: '10 000 $' },
  { label: 'Стан', value: 'Supabase' },
  { label: 'Логіка', value: 'Сервер' },
];

const pillars = [
  {
    title: 'Заробляй репутацію',
    text: 'Імідж посилює ділові зустрічі, відкриває вигідніші рішення та прямо впливає на премії.',
  },
  {
    title: 'Переходь у великий бізнес',
    text: 'Після серії успішних ділових зустрічей гравець може вийти із внутрішнього кола на зовнішнє.',
  },
  {
    title: 'Контролюй активи',
    text: 'Тендери, компанії, акції та директорські статуси формують шлях до фінальної перемоги.',
  },
];

function isLobbyRpcResult(value: unknown): value is LobbyRpcResult {
  return (
    typeof value === 'object' &&
    value !== null &&
    'game_id' in value &&
    'join_code' in value
  );
}

function readErrorMessage(error: unknown) {
  if (error instanceof Error) {
    return error.message;
  }

  if (typeof error === 'object' && error && 'message' in error) {
    const message = String(error.message);
    const details =
      'details' in error && error.details ? String(error.details) : null;
    const hint = 'hint' in error && error.hint ? String(error.hint) : null;

    return [message, details, hint].filter(Boolean).join(' ');
  }

  return 'Невідома помилка';
}

function readDisplayName(user: User) {
  const name =
    user.user_metadata.full_name ?? user.user_metadata.name ?? user.email;

  return typeof name === 'string' && name.trim() ? name : 'Гравець';
}

export default function HomePage() {
  const router = useRouter();
  const joinInputRef = useRef<HTMLInputElement | null>(null);
  const { openAuthModal, refreshUser, user } = useAuth();
  const [busyAction, setBusyAction] = useState<'create' | 'join' | null>(null);
  const [error, setError] = useState<string | null>(null);
  const isBusy = Boolean(busyAction);

  const createButtonLabel = useMemo(() => {
    if (busyAction === 'create') {
      return 'Створюємо...';
    }

    return 'Створити гру';
  }, [busyAction]);

  async function readCurrentUserOrOpenAuth() {
    const currentUser = user ?? (await refreshUser());

    if (!currentUser) {
      openAuthModal();
      return null;
    }

    return currentUser;
  }

  async function handleCreateGame() {
    setError(null);

    const currentUser = await readCurrentUserOrOpenAuth();

    if (!currentUser) {
      return;
    }

    setBusyAction('create');

    try {
      const supabase = getSupabaseClient();
      const { data, error: createError } = await supabase.rpc('create_game', {
        p_display_name: readDisplayName(currentUser),
        p_max_players: 6,
      });

      if (createError) {
        throw createError;
      }

      if (!isLobbyRpcResult(data)) {
        throw new Error('RPC create_game returned an unexpected response.');
      }

      router.push(`/lobby/${encodeURIComponent(data.join_code)}`);
    } catch (caughtError) {
      setError(readErrorMessage(caughtError));
    } finally {
      setBusyAction(null);
    }
  }

  async function handleHeroJoinClick() {
    const currentUser = await readCurrentUserOrOpenAuth();

    if (!currentUser) {
      openAuthModal();
      return;
    }

    joinInputRef.current?.focus();
  }

  async function handleJoinGame(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const form = event.currentTarget;
    const formData = new FormData(form);
    const joinCode = String(formData.get('code') ?? '').trim().toUpperCase();
    const currentUser = await readCurrentUserOrOpenAuth();

    if (!currentUser) {
      return;
    }

    if (!joinCode) {
      setError('Введіть код гри.');
      joinInputRef.current?.focus();
      return;
    }

    setBusyAction('join');
    setError(null);

    try {
      const supabase = getSupabaseClient();
      const { data, error: joinError } = await supabase.rpc('join_game', {
        p_display_name: readDisplayName(currentUser),
        p_join_code: joinCode,
      });

      if (joinError) {
        throw joinError;
      }

      if (!isLobbyRpcResult(data)) {
        throw new Error('RPC join_game returned an unexpected response.');
      }

      router.push(`/lobby/${encodeURIComponent(data.join_code)}`);
    } catch (caughtError) {
      setError(readErrorMessage(caughtError));
    } finally {
      setBusyAction(null);
    }
  }

  return (
    <div className="min-h-screen bg-slate-50 text-slate-950">
      <header className="border-b border-slate-200 bg-white shadow-sm">
        <div className="mx-auto flex w-full max-w-7xl items-center justify-between gap-4 px-6 py-4">
          <Link className="text-lg font-semibold tracking-normal" href="/">
            Економічна Монополія
          </Link>

          <nav className="hidden items-center gap-6 text-sm font-medium text-slate-600 md:flex">
            <Link className="text-slate-950" href="/">
              Головна
            </Link>
            <Link className="transition hover:text-slate-950" href="/rules">
              Правила гри
            </Link>
            <Link className="transition hover:text-slate-950" href="#start">
              Почати гру
            </Link>
          </nav>

          <AuthButton />
        </div>
      </header>

      <main>
        <section className="border-b border-slate-200 bg-white">
          <div className="mx-auto grid min-h-[calc(100vh-73px)] w-full max-w-7xl gap-10 px-6 py-12 lg:grid-cols-[minmax(0,1fr)_420px] lg:items-center lg:py-16">
            <div className="max-w-3xl">
              <p className="mb-4 text-sm font-semibold uppercase tracking-normal text-emerald-700">
                Онлайн з першого ходу
              </p>
              <h1 className="text-4xl font-bold tracking-normal text-slate-950 sm:text-5xl lg:text-6xl">
                Економічна Монополія
              </h1>
              <p className="mt-6 max-w-2xl text-lg leading-8 text-slate-700">
                Браузерна економічна настільна гра, де гравці проходять шлях
                від перших ділових зустрічей до контролю компаній, тендерів і виборів
                генерального директора.
              </p>

              {error ? (
                <p className="mt-5 rounded-md border border-rose-200 bg-rose-50 px-4 py-3 text-sm font-semibold text-rose-800">
                  {error}
                </p>
              ) : null}

              <div className="mt-8 grid gap-3 sm:grid-cols-2">
                <button
                  className="inline-flex h-12 items-center justify-center rounded-md bg-emerald-600 px-6 text-sm font-semibold text-white shadow-sm transition hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-slate-300"
                  disabled={isBusy}
                  onClick={handleCreateGame}
                  type="button"
                >
                  {createButtonLabel}
                </button>
                <button
                  className="inline-flex h-12 items-center justify-center rounded-md border border-slate-300 bg-white px-6 text-sm font-semibold text-slate-800 transition hover:border-slate-400 hover:bg-slate-100 disabled:cursor-not-allowed disabled:text-slate-300"
                  disabled={isBusy}
                  onClick={handleHeroJoinClick}
                  type="button"
                >
                  Приєднатися
                </button>
              </div>

              <dl className="mt-10 grid grid-cols-2 gap-3 sm:grid-cols-4">
                {facts.map((fact) => (
                  <div
                    className="rounded-md border border-slate-200 bg-slate-50 p-4"
                    key={fact.label}
                  >
                    <dt className="text-xs font-semibold uppercase tracking-normal text-slate-500">
                      {fact.label}
                    </dt>
                    <dd className="mt-1 text-xl font-bold text-slate-950">
                      {fact.value}
                    </dd>
                  </div>
                ))}
              </dl>
            </div>

            <aside className="rounded-md border border-slate-200 bg-slate-50 p-5">
              <div className="grid aspect-square grid-cols-7 grid-rows-7 gap-2">
                {Array.from({ length: 49 }).map((_, index) => {
                  const row = Math.floor(index / 7);
                  const col = index % 7;
                  const outer = row === 0 || row === 6 || col === 0 || col === 6;
                  const inner =
                    row >= 2 &&
                    row <= 4 &&
                    col >= 2 &&
                    col <= 4 &&
                    (row === 2 || row === 4 || col === 2 || col === 4);

                  if (!outer && !inner) {
                    return <div key={index} />;
                  }

                  return (
                    <div
                      className={
                        outer
                          ? 'rounded border border-slate-300 bg-white'
                          : 'rounded border border-emerald-300 bg-emerald-50'
                      }
                      key={index}
                    />
                  );
                })}
              </div>
              <div className="mt-5 grid grid-cols-3 gap-3 border-t border-slate-200 pt-4 text-center">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-normal text-slate-500">
                    Баланс
                  </p>
                  <p className="mt-1 font-bold text-slate-950">10 000 $</p>
                </div>
                <div>
                  <p className="text-xs font-semibold uppercase tracking-normal text-slate-500">
                    Імідж
                  </p>
                  <p className="mt-1 font-bold text-emerald-700">0</p>
                </div>
                <div>
                  <p className="text-xs font-semibold uppercase tracking-normal text-slate-500">
                    Зустрічі
                  </p>
                  <p className="mt-1 font-bold text-amber-700">7-10</p>
                </div>
              </div>
            </aside>
          </div>
        </section>

        <section className="bg-slate-50" id="start">
          <div className="mx-auto grid w-full max-w-7xl gap-8 px-6 py-12 lg:grid-cols-[1fr_360px]">
            <div>
              <h2 className="text-2xl font-bold tracking-normal text-slate-950">
                Як виграти
              </h2>
              <p className="mt-4 max-w-3xl text-base leading-7 text-slate-700">
                Перемога настає після успішних виборів генерального директора:
                кандидат має зібрати щонайменше 51% голосів активних
                директорів, а всі кидки та підрахунки виконує сервер.
              </p>

              <div className="mt-8 grid gap-4 md:grid-cols-3">
                {pillars.map((pillar) => (
                  <article
                    className="rounded-md border border-slate-200 bg-white p-5"
                    key={pillar.title}
                  >
                    <h3 className="text-base font-bold text-slate-950">
                      {pillar.title}
                    </h3>
                    <p className="mt-3 text-sm leading-6 text-slate-600">
                      {pillar.text}
                    </p>
                  </article>
                ))}
              </div>
            </div>

            <form
              className="rounded-md border border-slate-200 bg-white p-5"
              id="join"
              onSubmit={handleJoinGame}
            >
              <label
                className="text-sm font-semibold text-slate-700"
                htmlFor="join-code"
              >
                Код гри
              </label>
              <input
                className="mt-2 h-12 w-full rounded-md border border-slate-300 px-4 text-base font-semibold uppercase outline-none transition placeholder:font-normal placeholder:normal-case focus:border-emerald-600 focus:ring-4 focus:ring-emerald-100"
                id="join-code"
                name="code"
                placeholder="ABCD12"
                ref={joinInputRef}
                type="text"
              />
              <button
                className="mt-4 inline-flex h-12 w-full items-center justify-center rounded-md bg-slate-950 px-6 text-sm font-semibold text-white transition hover:bg-slate-800 disabled:cursor-not-allowed disabled:bg-slate-300"
                disabled={isBusy}
                type="submit"
              >
                {busyAction === 'join' ? 'Приєднуємось...' : 'Приєднатися'}
              </button>
            </form>
          </div>
        </section>
      </main>
    </div>
  );
}
