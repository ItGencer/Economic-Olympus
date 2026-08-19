'use client';

import { FormEvent, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';

import { useAuth } from '@/components/AuthProvider';
import SiteHeader from '@/components/SiteHeader';
import TestVersionBadge from '@/components/TestVersionBadge';
import {
  ensurePlayableUser,
  readPlayableUserName,
  runPlayableRpc,
} from '@/lib/supabase';

type LobbyRpcResult = {
  game_id: string;
  join_code: string;
  player_id?: string;
};

const facts = [
  { label: 'Гравці', value: '2-6' },
  { label: 'Старт', value: '10 000 $' },
  { label: 'Імідж', value: 'Впливає на угоди' },
  { label: 'Логіка', value: 'Сервер' },
];

const pillars = [
  {
    title: 'Будуй репутацію',
    text: 'Імідж відкриває сильніші ділові зустрічі, допомагає в рішеннях і може змінити темп партії.',
  },
  {
    title: 'Керуй ризиком',
    text: 'Казино, випадкові події та негативна репутація можуть різко змінити баланс і стратегію.',
  },
  {
    title: 'Контролюй активи',
    text: 'Компанії, тендери, акції та директори формують шлях до фінальної переваги.',
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

function BoardPreview() {
  return (
    <div className="relative mx-auto w-full max-w-[420px]">
      <div className="absolute -inset-4 rounded-[28px] bg-violet-500/20 blur-2xl" />
      <div className="neo-panel neo-grid-glow relative rounded-[22px] border border-violet-300/25 bg-white p-4 shadow-xl sm:p-5">
        <div className="grid aspect-square grid-cols-9 grid-rows-9 gap-1.5">
          {Array.from({ length: 81 }).map((_, index) => {
            const row = Math.floor(index / 9);
            const col = index % 9;
            const outer = row === 0 || row === 8 || col === 0 || col === 8;
            const inner =
              row >= 3 &&
              row <= 5 &&
              col >= 3 &&
              col <= 5 &&
              (row === 3 || row === 5 || col === 3 || col === 5);

            if (!outer && !inner) {
              return (
                <div
                  className="rounded-md bg-slate-50"
                  key={index}
                />
              );
            }

            return (
              <div
                className={
                  outer
                    ? 'rounded-md border border-violet-300/45 bg-white/8 shadow-sm'
                    : 'rounded-md border border-fuchsia-300/55 bg-violet-400/15'
                }
                key={index}
              />
            );
          })}
        </div>

        <div className="mt-5 grid grid-cols-3 gap-3 border-t border-slate-200 pt-4 text-center">
          <div>
            <p className="text-xs font-semibold uppercase text-slate-500">
              Баланс
            </p>
            <p className="mt-1 font-bold text-slate-950">10 000 $</p>
          </div>
          <div>
            <p className="text-xs font-semibold uppercase text-slate-500">
              Імідж
            </p>
            <p className="mt-1 font-bold text-emerald-700">0</p>
          </div>
          <div>
            <p className="text-xs font-semibold uppercase text-slate-500">
              Зустрічі
            </p>
            <p className="mt-1 font-bold text-amber-700">7-10</p>
          </div>
        </div>
      </div>
    </div>
  );
}

export default function HomePage() {
  const router = useRouter();
  const joinInputRef = useRef<HTMLInputElement | null>(null);
  const { refreshUser, user } = useAuth();
  const [busyAction, setBusyAction] = useState<'create' | 'join' | null>(null);
  const [error, setError] = useState<string | null>(null);
  const isBusy = Boolean(busyAction);

  const createButtonLabel = useMemo(() => {
    if (busyAction === 'create') {
      return 'Створюємо...';
    }

    return 'Створити гру';
  }, [busyAction]);

  async function readCurrentPlayableUser() {
    const currentUser = user ?? (await refreshUser());

    if (currentUser) {
      return currentUser;
    }

    const testUser = await ensurePlayableUser();
    await refreshUser();

    return testUser;
  }

  async function handleCreateGame() {
    setError(null);
    setBusyAction('create');

    try {
      const currentUser = await readCurrentPlayableUser();
      const { data, error: createError } = await runPlayableRpc('create_game', {
        p_display_name: readPlayableUserName(currentUser),
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
    joinInputRef.current?.focus();
  }

  async function handleJoinGame(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const form = event.currentTarget;
    const formData = new FormData(form);
    const joinCode = String(formData.get('code') ?? '').trim().toUpperCase();

    if (!joinCode) {
      setError('Введіть код гри.');
      joinInputRef.current?.focus();
      return;
    }

    setBusyAction('join');
    setError(null);

    try {
      const currentUser = await readCurrentPlayableUser();
      const { data, error: joinError } = await runPlayableRpc('join_game', {
        p_display_name: readPlayableUserName(currentUser),
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
    <div className="min-h-screen text-slate-950">
      <SiteHeader />

      <main>
        <section className="neo-grid-glow border-b border-violet-300/20 bg-white">
          <div className="mx-auto grid w-full max-w-7xl gap-10 px-4 py-10 sm:px-6 lg:grid-cols-[minmax(0,1fr)_minmax(320px,440px)] lg:items-center lg:py-16">
            <div className="max-w-3xl">
              <p className="mb-4 text-sm font-bold uppercase tracking-normal text-emerald-700">
                Онлайн з першого ходу
              </p>
              <h1 className="neo-hero-title text-4xl font-black tracking-normal text-slate-950 sm:text-5xl lg:text-6xl">
                Economic Olympus
              </h1>
              <p className="mt-6 max-w-2xl text-base leading-8 text-slate-700 sm:text-lg">
                Браузерна економічна настільна гра про репутацію, ризик,
                переговори і контроль активів. Створюй партію, запрошуй друзів
                і проходь шлях від перших угод до великого бізнесу.
              </p>
              <div className="mt-6 max-w-2xl rounded-[18px] border border-amber-300/35 bg-amber-300/10 px-4 py-4 shadow-[0_0_24px_rgba(251,191,36,0.12)]">
                <TestVersionBadge />
                <p className="mt-3 text-sm font-semibold leading-6 text-amber-50">
                  Альфа-режим для тестування: можна створити гру або
                  приєднатися без Google-входу. Сайт автоматично створить
                  тимчасову тестову сесію гравця.
                </p>
              </div>

              {error ? (
                <p className="mt-5 rounded-md border border-rose-200 bg-rose-50 px-4 py-3 text-sm font-semibold text-rose-800">
                  {error}
                </p>
              ) : null}

              <div className="mt-8 grid gap-3 sm:grid-cols-2">
                <button
                  className="neo-button inline-flex h-12 items-center justify-center rounded-[18px] bg-emerald-600 px-6 text-sm font-bold text-white shadow-lg shadow-emerald-900/10 transition hover:-translate-y-0.5 hover:bg-emerald-700 disabled:translate-y-0 disabled:cursor-not-allowed disabled:bg-slate-300 disabled:shadow-none"
                  disabled={isBusy}
                  onClick={handleCreateGame}
                  type="button"
                >
                  {createButtonLabel}
                </button>
                <button
                  className="neo-button inline-flex h-12 items-center justify-center rounded-[18px] border border-slate-300 bg-white px-6 text-sm font-bold text-slate-800 shadow-sm transition hover:-translate-y-0.5 hover:border-slate-400 hover:bg-slate-100 disabled:translate-y-0 disabled:cursor-not-allowed disabled:text-slate-300"
                  disabled={isBusy}
                  onClick={handleHeroJoinClick}
                  type="button"
                >
                  Приєднатися
                </button>
              </div>

              <dl className="mt-8 grid grid-cols-2 gap-3 sm:grid-cols-4">
                {facts.map((fact) => (
                  <div
                    className="neo-panel rounded-[18px] border border-slate-200 bg-slate-50 p-4"
                    key={fact.label}
                  >
                    <dt className="text-xs font-bold uppercase tracking-normal text-slate-500">
                      {fact.label}
                    </dt>
                    <dd className="mt-1 text-lg font-black text-slate-950">
                      {fact.value}
                    </dd>
                  </div>
                ))}
              </dl>
            </div>

            <BoardPreview />
          </div>
        </section>

        <section className="bg-slate-50" id="start">
          <div className="mx-auto grid w-full max-w-7xl gap-8 px-4 py-10 sm:px-6 lg:grid-cols-[1fr_360px] lg:py-14">
            <div>
              <p className="text-sm font-bold uppercase tracking-normal text-emerald-700">
                Мета партії
              </p>
              <h2 className="mt-3 text-2xl font-black tracking-normal text-slate-950 sm:text-3xl">
                Виграй вибори генерального директора
              </h2>
              <p className="mt-4 max-w-3xl text-base leading-7 text-slate-700">
                Перемога настає після успішних виборів: кандидат має зібрати
                щонайменше 51% голосів активних директорів, а всі кидки,
                події та підрахунки виконує сервер.
              </p>

              <div className="mt-8 grid gap-4 md:grid-cols-3">
                {pillars.map((pillar) => (
                  <article
                    className="neo-panel rounded-[18px] border border-slate-200 bg-white p-5 shadow-sm"
                    key={pillar.title}
                  >
                    <h3 className="text-base font-black text-slate-950">
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
              className="neo-panel rounded-[18px] border border-slate-200 bg-white p-5 shadow-sm"
              id="join"
              onSubmit={handleJoinGame}
            >
              <label
                className="text-sm font-bold text-slate-700"
                htmlFor="join-code"
              >
                Код гри
              </label>
              <input
                className="mt-2 h-12 w-full rounded-[16px] border border-slate-300 px-4 text-base font-bold uppercase outline-none transition placeholder:font-normal placeholder:normal-case focus:border-violet-400 focus:ring-4 focus:ring-violet-400/20"
                id="join-code"
                name="code"
                placeholder="ABCD12"
                ref={joinInputRef}
                type="text"
              />
              <button
                className="neo-button mt-4 inline-flex h-12 w-full items-center justify-center rounded-[18px] bg-slate-950 px-6 text-sm font-bold text-white transition hover:bg-slate-800 disabled:cursor-not-allowed disabled:bg-slate-300"
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
