'use client';

import type { User } from '@supabase/supabase-js';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useMemo, useState } from 'react';

import AuthButton from '@/components/AuthButton';
import { useAuth } from '@/components/AuthProvider';
import { getSupabaseClient } from '@/lib/supabase';

type ProfileGameStatus = 'lobby' | 'in_progress' | 'finished';

type ProfileGameRow = {
  created_at: string;
  finished_at: string | null;
  id: string;
  join_code: string;
  started_at: string | null;
  status: ProfileGameStatus;
  winner_player_id: string | null;
};

type PlayerGameRow = {
  created_at: string;
  display_name: string;
  game: ProfileGameRow | ProfileGameRow[] | null;
  id: string;
  seat_number: number;
};

type ProfileGame = {
  createdAt: string;
  displayName: string;
  game: ProfileGameRow;
  playerId: string;
  seatNumber: number;
};

const dateFormatter = new Intl.DateTimeFormat('uk-UA', {
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  month: 'short',
});

const statusLabels: Record<ProfileGameStatus, string> = {
  finished: 'Завершена',
  in_progress: 'Активна',
  lobby: 'Лобі',
};

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

function readUserName(user: User | null) {
  if (!user) {
    return 'Гравець';
  }

  const name =
    user.user_metadata.full_name ?? user.user_metadata.name ?? user.email;

  return typeof name === 'string' && name.trim() ? name : 'Гравець';
}

function readAvatarUrl(user: User | null) {
  if (!user) {
    return null;
  }

  const avatarUrl = user.user_metadata.avatar_url ?? user.user_metadata.picture;

  return typeof avatarUrl === 'string' && avatarUrl.trim() ? avatarUrl : null;
}

function readGame(row: PlayerGameRow) {
  if (Array.isArray(row.game)) {
    return row.game[0] ?? null;
  }

  return row.game;
}

function normalizeProfileGame(row: PlayerGameRow): ProfileGame | null {
  const game = readGame(row);

  if (!game) {
    return null;
  }

  return {
    createdAt: row.created_at,
    displayName: row.display_name,
    game,
    playerId: row.id,
    seatNumber: row.seat_number,
  };
}

function formatDate(value?: string | null) {
  if (!value) {
    return 'немає';
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return 'немає';
  }

  return dateFormatter.format(date);
}

function getGameHref(game: ProfileGameRow) {
  const code = encodeURIComponent(game.join_code);

  return game.status === 'lobby' ? `/lobby/${code}` : `/play/${code}`;
}

function GameList({
  emptyText,
  endingGameId,
  games,
  onEndGame,
  title,
}: {
  emptyText: string;
  endingGameId?: string | null;
  games: ProfileGame[];
  onEndGame?: (game: ProfileGameRow) => void;
  title: string;
}) {
  return (
    <section className="min-w-0">
      <div className="mb-3 flex items-center justify-between gap-3">
        <h2 className="text-lg font-bold text-slate-950">{title}</h2>
        <span className="rounded-md bg-slate-100 px-2.5 py-1 text-xs font-bold text-slate-600">
          {games.length}
        </span>
      </div>

      {games.length > 0 ? (
        <div className="grid gap-3">
          {games.map(({ createdAt, displayName, game, playerId, seatNumber }) => (
            <article
              className="rounded-md border border-slate-200 bg-white p-4 shadow-sm"
              key={`${game.id}-${playerId}`}
            >
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0">
                  <p className="text-xs font-semibold uppercase tracking-normal text-emerald-700">
                    {game.join_code}
                  </p>
                  <h3 className="mt-1 truncate text-base font-bold text-slate-950">
                    {statusLabels[game.status]}
                  </h3>
                </div>
                <div className="flex shrink-0 flex-col gap-2">
                  <Link
                    className="inline-flex h-9 items-center justify-center rounded-md border border-slate-300 px-3 text-xs font-bold text-slate-700 transition hover:bg-slate-50"
                    href={getGameHref(game)}
                  >
                    Відкрити
                  </Link>
                  {onEndGame ? (
                    <button
                      className="inline-flex h-9 items-center justify-center rounded-md border border-rose-200 px-3 text-xs font-bold text-rose-700 transition hover:bg-rose-50 disabled:cursor-not-allowed disabled:text-slate-300"
                      disabled={endingGameId === game.id}
                      onClick={() => onEndGame(game)}
                      type="button"
                    >
                      {endingGameId === game.id ? 'Завершуємо' : 'Завершити'}
                    </button>
                  ) : null}
                </div>
              </div>

              <dl className="mt-4 grid grid-cols-2 gap-3 text-sm">
                <div>
                  <dt className="text-xs font-semibold text-slate-500">
                    Місце
                  </dt>
                  <dd className="mt-1 font-bold text-slate-950">
                    #{seatNumber}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs font-semibold text-slate-500">
                    Ім'я в грі
                  </dt>
                  <dd className="mt-1 truncate font-bold text-slate-950">
                    {displayName}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs font-semibold text-slate-500">
                    Приєднання
                  </dt>
                  <dd className="mt-1 font-bold text-slate-950">
                    {formatDate(createdAt)}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs font-semibold text-slate-500">
                    Старт
                  </dt>
                  <dd className="mt-1 font-bold text-slate-950">
                    {formatDate(game.started_at)}
                  </dd>
                </div>
              </dl>
            </article>
          ))}
        </div>
      ) : (
        <p className="rounded-md border border-dashed border-slate-300 bg-white px-4 py-5 text-sm font-semibold text-slate-500">
          {emptyText}
        </p>
      )}
    </section>
  );
}

export default function ProfilePage() {
  const router = useRouter();
  const {
    loading: authLoading,
    openAuthModal,
    refreshUser,
    user,
  } = useAuth();
  const [error, setError] = useState<string | null>(null);
  const [games, setGames] = useState<ProfileGame[]>([]);
  const [gamesLoading, setGamesLoading] = useState(false);
  const [endingGameId, setEndingGameId] = useState<string | null>(null);

  useEffect(() => {
    let active = true;

    async function loadProfile() {
      if (authLoading) {
        return;
      }

      const currentUser = user ?? (await refreshUser());

      if (!active) {
        return;
      }

      if (!currentUser) {
        openAuthModal();
        router.replace('/');
        return;
      }

      setGamesLoading(true);
      setError(null);

      try {
        const supabase = getSupabaseClient();
        const { data, error: profileError } = await supabase
          .from('players')
          .select(
            [
              'id',
              'seat_number',
              'display_name',
              'created_at',
              'game:games!players_game_id_fkey(id, join_code, status, created_at, started_at, finished_at, winner_player_id)',
            ].join(', '),
          )
          .eq('user_id', currentUser.id)
          .order('created_at', { ascending: false });

        if (!active) {
          return;
        }

        if (profileError) {
          throw profileError;
        }

        setGames(
          ((data ?? []) as unknown as PlayerGameRow[])
            .map(normalizeProfileGame)
            .filter((game): game is ProfileGame => Boolean(game)),
        );
      } catch (caughtError) {
        if (active) {
          setError(readErrorMessage(caughtError));
          setGames([]);
        }
      } finally {
        if (active) {
          setGamesLoading(false);
        }
      }
    }

    void loadProfile();

    return () => {
      active = false;
    };
  }, [authLoading, openAuthModal, refreshUser, router, user]);

  async function handleEndGame(game: ProfileGameRow) {
    if (game.status === 'finished' || endingGameId) {
      return;
    }

    const confirmed = window.confirm(
      'Завершити цю гру зараз? Вона перейде в завершені без переможця.',
    );

    if (!confirmed) {
      return;
    }

    setEndingGameId(game.id);
    setError(null);

    try {
      const supabase = getSupabaseClient();
      const { error: endError } = await supabase.rpc('end_game', {
        p_game_id: game.id,
      });

      if (endError) {
        throw endError;
      }

      const finishedAt = new Date().toISOString();

      setGames((currentGames) =>
        currentGames.map((profileGame) =>
          profileGame.game.id === game.id
            ? {
                ...profileGame,
                game: {
                  ...profileGame.game,
                  finished_at: finishedAt,
                  status: 'finished',
                  winner_player_id: null,
                },
              }
            : profileGame,
        ),
      );
    } catch (caughtError) {
      setError(readErrorMessage(caughtError));
    } finally {
      setEndingGameId(null);
    }
  }

  const groupedGames = useMemo(
    () => ({
      active: games.filter(({ game }) => game.status === 'in_progress'),
      finished: games.filter(({ game }) => game.status === 'finished'),
      lobby: games.filter(({ game }) => game.status === 'lobby'),
    }),
    [games],
  );

  const stats = useMemo(() => {
    const played = groupedGames.finished.length;
    const wins = groupedGames.finished.filter(
      ({ game, playerId }) => game.winner_player_id === playerId,
    ).length;

    return [
      { label: 'Зіграно', value: String(played) },
      { label: 'Перемоги', value: String(wins) },
      { label: 'Активні', value: String(groupedGames.active.length) },
      { label: 'Лобі', value: String(groupedGames.lobby.length) },
    ];
  }, [groupedGames]);

  const userName = readUserName(user);
  const avatarUrl = readAvatarUrl(user);
  const initial = userName.trim().charAt(0).toUpperCase() || 'U';

  return (
    <div className="min-h-screen bg-slate-50 text-slate-950">
      <header className="border-b border-slate-200 bg-white shadow-sm">
        <div className="mx-auto flex w-full max-w-7xl items-center justify-between gap-4 px-6 py-4">
          <Link className="text-lg font-semibold tracking-normal" href="/">
            Економічна Монополія
          </Link>

          <nav className="hidden items-center gap-6 text-sm font-medium text-slate-600 md:flex">
            <Link className="transition hover:text-slate-950" href="/">
              Головна
            </Link>
            <Link className="transition hover:text-slate-950" href="/rules">
              Правила гри
            </Link>
          </nav>

          <AuthButton />
        </div>
      </header>

      <main>
        <section className="border-b border-slate-200 bg-white">
          <div className="mx-auto flex w-full max-w-7xl flex-col gap-6 px-6 py-8 md:flex-row md:items-center md:justify-between">
            <div className="flex min-w-0 items-center gap-4">
              <span
                aria-hidden="true"
                className="grid h-16 w-16 shrink-0 place-items-center rounded-full bg-slate-900 bg-cover bg-center text-xl font-bold text-white"
                style={
                  avatarUrl ? { backgroundImage: `url(${avatarUrl})` } : undefined
                }
              >
                {avatarUrl ? null : initial}
              </span>
              <div className="min-w-0">
                <p className="text-sm font-semibold uppercase tracking-normal text-emerald-700">
                  Кабінет гравця
                </p>
                <h1 className="mt-1 truncate text-3xl font-bold tracking-normal text-slate-950">
                  {authLoading || !user ? 'Перевіряємо сесію...' : userName}
                </h1>
                {user?.email ? (
                  <p className="mt-1 truncate text-sm font-semibold text-slate-500">
                    {user.email}
                  </p>
                ) : null}
              </div>
            </div>
          </div>
        </section>

        <section className="mx-auto w-full max-w-7xl px-6 py-8">
          {error ? (
            <p className="mb-6 rounded-md border border-rose-200 bg-rose-50 px-4 py-3 text-sm font-semibold text-rose-800">
              {error}
            </p>
          ) : null}

          <dl className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {stats.map((stat) => (
              <div
                className="rounded-md border border-slate-200 bg-white p-4 shadow-sm"
                key={stat.label}
              >
                <dt className="text-xs font-semibold uppercase tracking-normal text-slate-500">
                  {stat.label}
                </dt>
                <dd className="mt-2 text-2xl font-bold text-slate-950">
                  {stat.value}
                </dd>
              </div>
            ))}
          </dl>

          {authLoading || gamesLoading ? (
            <p className="mt-8 rounded-md border border-slate-200 bg-white px-4 py-5 text-sm font-semibold text-slate-500">
              Завантажуємо кабінет...
            </p>
          ) : (
            <div className="mt-8 grid gap-8 lg:grid-cols-3">
              <GameList
                emptyText="Активних ігор поки немає."
                endingGameId={endingGameId}
                games={groupedGames.active}
                onEndGame={handleEndGame}
                title="Активні"
              />
              <GameList
                emptyText="Лобі в очікуванні поки немає."
                games={groupedGames.lobby}
                title="Лобі"
              />
              <GameList
                emptyText="Завершених ігор поки немає."
                games={groupedGames.finished}
                title="Завершені"
              />
            </div>
          )}
        </section>
      </main>
    </div>
  );
}
