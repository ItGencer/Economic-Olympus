'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from 'react';

import AuthButton from '@/components/AuthButton';
import ConnectionStatus from '@/components/ConnectionStatus';
import type { GameRealtimeStatus } from '@/hooks/useGameRealtime';
import { getSupabaseClient, requireAuthenticatedUser } from '@/lib/supabase';

type GameStatus = 'lobby' | 'in_progress' | 'finished';

type GameRow = {
  id: string;
  status: GameStatus;
  join_code: string;
  max_players: number;
  current_turn_player_id: string | null;
  created_by_user_id: string | null;
  started_at: string | null;
};

type PlayerRow = {
  id: string;
  game_id: string;
  user_id: string | null;
  seat_number: number;
  display_name: string;
  is_bot: boolean;
  created_at: string;
};

type LobbyRpcResult = {
  game_id: string;
  join_code: string;
  player_id?: string;
};

type LobbyPageProps = {
  params: {
    code: string;
  };
};

function normalizeJoinCode(value: string) {
  return decodeURIComponent(value).trim().toUpperCase();
}

function readBrowserOnline() {
  return typeof navigator === 'undefined' ? true : navigator.onLine;
}

function readErrorMessage(error: unknown) {
  if (error instanceof Error) {
    return error.message;
  }

  if (typeof error === 'object' && error && 'message' in error) {
    return String(error.message);
  }

  return 'Невідома помилка';
}

function isLobbyRpcResult(value: unknown): value is LobbyRpcResult {
  return (
    typeof value === 'object' &&
    value !== null &&
    'game_id' in value &&
    'join_code' in value
  );
}

function toRealtimeStatus(status: string): GameRealtimeStatus {
  if (status === 'SUBSCRIBED') {
    return 'subscribed';
  }

  if (status === 'CHANNEL_ERROR') {
    return 'channel_error';
  }

  if (status === 'TIMED_OUT') {
    return 'timed_out';
  }

  if (status === 'CLOSED') {
    return 'closed';
  }

  return 'connecting';
}

export default function LobbyPage({ params }: LobbyPageProps) {
  const router = useRouter();
  const joinCode = useMemo(() => normalizeJoinCode(params.code), [params.code]);
  const isCreateRoute = joinCode === 'NEW';
  const creationStartedRef = useRef(false);

  const [game, setGame] = useState<GameRow | null>(null);
  const [players, setPlayers] = useState<PlayerRow[]>([]);
  const [currentUserId, setCurrentUserId] = useState<string | null>(null);
  const [displayName, setDisplayName] = useState('Гравець');
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isBrowserOnline, setIsBrowserOnline] = useState(readBrowserOnline);
  const [lastSyncedAt, setLastSyncedAt] = useState<string | null>(null);
  const [realtimeStatus, setRealtimeStatus] =
    useState<GameRealtimeStatus>('idle');
  const [refreshing, setRefreshing] = useState(false);

  const currentPlayer = useMemo(
    () => players.find((player) => player.user_id === currentUserId) ?? null,
    [currentUserId, players],
  );
  const isOwner = Boolean(game && currentUserId === game.created_by_user_id);
  const canJoin = Boolean(game && game.status === 'lobby' && !currentPlayer);
  const canAddBot = Boolean(
    game &&
      game.status === 'lobby' &&
      isOwner &&
      players.length < game.max_players,
  );
  const canStart = Boolean(
    game &&
      game.status === 'lobby' &&
      isOwner &&
      players.length >= 2 &&
      players.length <= game.max_players,
  );

  const loadLobby = useCallback(
    async (targetCode = joinCode) => {
      if (targetCode === 'NEW') {
        return;
      }

      const supabase = getSupabaseClient();
      const { data: gameData, error: gameError } = await supabase
        .from('games')
        .select(
          'id,status,join_code,max_players,current_turn_player_id,created_by_user_id,started_at',
        )
        .eq('join_code', targetCode)
        .maybeSingle();

      if (gameError) {
        throw gameError;
      }

      if (!gameData) {
        setGame(null);
        setPlayers([]);
        setLastSyncedAt(new Date().toISOString());
        return;
      }

      const nextGame = gameData as GameRow;
      const { data: playersData, error: playersError } = await supabase
        .from('players')
        .select('id,game_id,user_id,seat_number,display_name,is_bot,created_at')
        .eq('game_id', nextGame.id)
        .order('seat_number', { ascending: true });

      if (playersError) {
        throw playersError;
      }

      setGame(nextGame);
      setPlayers((playersData ?? []) as PlayerRow[]);
      setLastSyncedAt(new Date().toISOString());
    },
    [joinCode],
  );

  const refreshLobby = useCallback(async () => {
    if (isCreateRoute) {
      return;
    }

    setRefreshing(true);
    setError(null);

    try {
      await loadLobby();
    } catch (caughtError) {
      setError(readErrorMessage(caughtError));
    } finally {
      setRefreshing(false);
    }
  }, [isCreateRoute, loadLobby]);

  useEffect(() => {
    let cancelled = false;

    async function createGame() {
      if (!isCreateRoute || creationStartedRef.current) {
        return;
      }

      const creationKey = 'economic-olympus-create-game-in-flight';

      if (window.sessionStorage.getItem(creationKey)) {
        setLoading(false);
        return;
      }

      creationStartedRef.current = true;
      window.sessionStorage.setItem(creationKey, '1');
      setLoading(true);
      setError(null);

      try {
        await requireAuthenticatedUser();
        const supabase = getSupabaseClient();
        const { data, error: createError } = await supabase.rpc('create_game', {
          p_display_name: displayName,
          p_max_players: 6,
        });

        if (createError) {
          throw createError;
        }

        if (!isLobbyRpcResult(data)) {
          throw new Error('RPC create_game returned an unexpected response.');
        }

        if (!cancelled) {
          router.replace(`/lobby/${data.join_code}`);
        }
      } catch (caughtError) {
        if (!cancelled) {
          setError(readErrorMessage(caughtError));
          setLoading(false);
        }
      } finally {
        window.sessionStorage.removeItem(creationKey);
      }
    }

    createGame();

    return () => {
      cancelled = true;
    };
  }, [displayName, isCreateRoute, router]);

  useEffect(() => {
    let cancelled = false;

    async function initializeLobby() {
      if (isCreateRoute) {
        return;
      }

      setLoading(true);
      setError(null);

      try {
        const user = await requireAuthenticatedUser();

        if (!cancelled) {
          setCurrentUserId(user.id);
        }

        await loadLobby();
      } catch (caughtError) {
        if (!cancelled) {
          setError(readErrorMessage(caughtError));
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    initializeLobby();

    return () => {
      cancelled = true;
    };
  }, [isCreateRoute, loadLobby]);

  useEffect(() => {
    if (!game?.id) {
      setRealtimeStatus('idle');
      return;
    }

    const supabase = getSupabaseClient();
    const channel = supabase
      .channel(`game:${game.id}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'players',
          filter: `game_id=eq.${game.id}`,
        },
        () => {
          void loadLobby(game.join_code);
        },
      )
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'games',
          filter: `id=eq.${game.id}`,
        },
        () => {
          void loadLobby(game.join_code);
        },
      )
      .subscribe((status) => {
        const nextStatus = toRealtimeStatus(status);

        setRealtimeStatus(nextStatus);

        if (nextStatus === 'channel_error' || nextStatus === 'timed_out') {
          void refreshLobby();
        }
      });

    setRealtimeStatus('connecting');

    return () => {
      void supabase.removeChannel(channel);
    };
  }, [game?.id, game?.join_code, loadLobby, refreshLobby]);

  useEffect(() => {
    if (isCreateRoute) {
      return;
    }

    function handleOnline() {
      setIsBrowserOnline(true);
      void refreshLobby();
    }

    function handleOffline() {
      setIsBrowserOnline(false);
    }

    function handleVisibilityChange() {
      if (document.visibilityState === 'visible') {
        void refreshLobby();
      }
    }

    setIsBrowserOnline(readBrowserOnline());
    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);
    document.addEventListener('visibilitychange', handleVisibilityChange);

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [isCreateRoute, refreshLobby]);

  async function handleJoin(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!game) {
      return;
    }

    setBusy(true);
    setError(null);

    try {
      const user = await requireAuthenticatedUser();
      setCurrentUserId(user.id);

      const supabase = getSupabaseClient();
      const { data, error: joinError } = await supabase.rpc('join_game', {
        p_display_name: displayName,
        p_join_code: game.join_code,
      });

      if (joinError) {
        throw joinError;
      }

      if (!isLobbyRpcResult(data)) {
        throw new Error('RPC join_game returned an unexpected response.');
      }

      await loadLobby(game.join_code);
    } catch (caughtError) {
      setError(readErrorMessage(caughtError));
    } finally {
      setBusy(false);
    }
  }

  async function handleAddBot() {
    if (!game || !canAddBot) {
      return;
    }

    setBusy(true);
    setError(null);

    try {
      const supabase = getSupabaseClient();
      const { error: addBotError } = await supabase.rpc('add_bot', {
        p_game_id: game.id,
      });

      if (addBotError) {
        throw addBotError;
      }

      await loadLobby(game.join_code);
    } catch (caughtError) {
      setError(readErrorMessage(caughtError));
    } finally {
      setBusy(false);
    }
  }

  async function handleRemoveBot(playerId: string) {
    if (!game || !isOwner || game.status !== 'lobby') {
      return;
    }

    setBusy(true);
    setError(null);

    try {
      const supabase = getSupabaseClient();
      const { error: removeBotError } = await supabase.rpc('remove_bot', {
        p_player_id: playerId,
      });

      if (removeBotError) {
        throw removeBotError;
      }

      await loadLobby(game.join_code);
    } catch (caughtError) {
      setError(readErrorMessage(caughtError));
    } finally {
      setBusy(false);
    }
  }

  async function handleStartGame() {
    if (!game || !canStart) {
      return;
    }

    setBusy(true);
    setError(null);

    try {
      const supabase = getSupabaseClient();
      const { error: startError } = await supabase.rpc('start_game', {
        p_game_id: game.id,
      });

      if (startError) {
        throw startError;
      }

      await loadLobby(game.join_code);
      router.push(`/play/${encodeURIComponent(game.join_code)}`);
    } catch (caughtError) {
      setError(readErrorMessage(caughtError));
    } finally {
      setBusy(false);
    }
  }

  async function handleLeaveGame() {
    if (!game || !currentPlayer || game.status !== 'lobby') {
      return;
    }

    setBusy(true);
    setError(null);

    try {
      const supabase = getSupabaseClient();
      const { error: leaveError } = await supabase.rpc('leave_game', {
        p_game_id: game.id,
      });

      if (leaveError) {
        throw leaveError;
      }

      router.replace('/');
    } catch (caughtError) {
      setError(readErrorMessage(caughtError));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="min-h-screen bg-slate-50 text-slate-950">
      <header className="border-b border-slate-200 bg-white shadow-sm">
        <div className="mx-auto flex w-full max-w-7xl items-center justify-between px-6 py-4">
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
            <Link className="text-slate-950" href="/lobby/new">
              Почати гру
            </Link>
          </nav>
          <AuthButton />
        </div>
      </header>

      <main className="mx-auto grid w-full max-w-7xl gap-6 px-6 py-8 lg:grid-cols-[minmax(0,1fr)_360px]">
        <section className="rounded-md border border-slate-200 bg-white p-6">
          <div className="flex flex-col gap-4 border-b border-slate-200 pb-6 md:flex-row md:items-start md:justify-between">
            <div>
              <p className="text-sm font-semibold uppercase tracking-normal text-emerald-700">
                Лобі
              </p>
              <h1 className="mt-2 text-3xl font-bold tracking-normal text-slate-950">
                {isCreateRoute ? 'Створення гри' : `Код гри ${joinCode}`}
              </h1>
              <p className="mt-3 max-w-2xl text-sm leading-6 text-slate-600">
                Приєднання дозволене тільки поки гра у статусі lobby. Після
                старту серверна RPC-функція блокує нові входи незалежно від UI.
              </p>
            </div>

            {game ? (
              <div className="rounded-md border border-slate-200 px-4 py-3 text-sm">
                <p className="font-semibold text-slate-500">Статус</p>
                <p className="mt-1 text-lg font-bold text-slate-950">
                  {game.status}
                </p>
              </div>
            ) : null}
          </div>

          {loading ? (
            <p className="py-8 text-sm text-slate-600">
              {isCreateRoute ? 'Створюємо лобі...' : 'Завантажуємо лобі...'}
            </p>
          ) : null}

          {error ? (
            <div className="mt-6 rounded-md border border-red-200 bg-red-50 px-4 py-3 text-sm font-medium text-red-800">
              {error}
            </div>
          ) : null}

          {!loading && !game && !isCreateRoute ? (
            <div className="mt-6 rounded-md border border-slate-200 bg-slate-50 p-5">
              <h2 className="text-lg font-bold text-slate-950">
                Лобі не знайдено
              </h2>
              <p className="mt-2 text-sm leading-6 text-slate-600">
                Перевір код гри або створи нову сесію.
              </p>
              <Link
                className="mt-4 inline-flex h-10 items-center justify-center rounded-md bg-emerald-600 px-4 text-sm font-semibold text-white transition hover:bg-emerald-700"
                href="/lobby/new"
              >
                Створити гру
              </Link>
            </div>
          ) : null}

          {game ? (
            <div className="mt-6">
              <div className="mb-3 flex items-center justify-between">
                <h2 className="text-xl font-bold text-slate-950">Гравці</h2>
                <div className="flex items-center gap-3">
                  <span className="text-sm font-semibold text-slate-500">
                    {players.length}/{game.max_players}
                  </span>
                  {isOwner && game.status === 'lobby' ? (
                    <button
                      className="inline-flex h-9 items-center justify-center rounded-md border border-emerald-200 px-3 text-xs font-bold text-emerald-700 transition hover:bg-emerald-50 disabled:cursor-not-allowed disabled:text-slate-300"
                      disabled={busy || !canAddBot}
                      onClick={handleAddBot}
                      type="button"
                    >
                      Додати бота
                    </button>
                  ) : null}
                </div>
              </div>

              <div className="grid gap-3 md:grid-cols-2">
                {players.map((player) => (
                  <article
                    className="rounded-md border border-slate-200 bg-slate-50 p-4"
                    key={player.id}
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <p className="text-sm font-semibold text-slate-500">
                          Місце {player.seat_number}
                        </p>
                        <h3 className="mt-1 text-lg font-bold text-slate-950">
                          {player.display_name}
                          {player.is_bot ? (
                            <span className="ml-2 align-middle rounded bg-slate-200 px-2 py-1 text-xs font-bold text-slate-700">
                              Бот
                            </span>
                          ) : null}
                        </h3>
                      </div>
                      <div className="flex shrink-0 flex-col items-end gap-2">
                        {player.user_id === currentUserId ? (
                          <span className="rounded bg-emerald-100 px-2 py-1 text-xs font-bold text-emerald-800">
                            Ви
                          </span>
                        ) : null}
                        {isOwner && game.status === 'lobby' && player.is_bot ? (
                          <button
                            className="rounded border border-rose-200 px-2 py-1 text-xs font-bold text-rose-700 transition hover:bg-rose-50 disabled:cursor-not-allowed disabled:text-slate-300"
                            disabled={busy}
                            onClick={() => void handleRemoveBot(player.id)}
                            type="button"
                          >
                            Прибрати
                          </button>
                        ) : null}
                      </div>
                    </div>
                    <p className="mt-3 text-sm text-slate-600">
                      {player.is_bot ? 'Бот' : 'Гравець'} · стартовий баланс
                      10 000 $
                    </p>
                  </article>
                ))}
              </div>
            </div>
          ) : null}
        </section>

        <aside className="space-y-4">
          <ConnectionStatus
            isOnline={isBrowserOnline}
            lastSyncedAt={lastSyncedAt}
            onRefresh={refreshLobby}
            realtimeStatus={game ? realtimeStatus : undefined}
            refreshing={refreshing}
          />

          <section className="rounded-md border border-slate-200 bg-white p-5">
            <h2 className="text-lg font-bold text-slate-950">Код запрошення</h2>
            <div className="mt-3 rounded-md border border-dashed border-slate-300 bg-slate-50 px-4 py-3 text-center text-2xl font-bold tracking-normal">
              {isCreateRoute ? '...' : joinCode}
            </div>
          </section>

          {game && canJoin ? (
            <form
              className="rounded-md border border-slate-200 bg-white p-5"
              onSubmit={handleJoin}
            >
              <label
                className="text-sm font-semibold text-slate-700"
                htmlFor="display-name"
              >
                Ім'я гравця
              </label>
              <input
                className="mt-2 h-11 w-full rounded-md border border-slate-300 px-3 outline-none transition focus:border-emerald-600 focus:ring-4 focus:ring-emerald-100"
                id="display-name"
                maxLength={32}
                onChange={(event) => setDisplayName(event.target.value)}
                value={displayName}
              />
              <button
                className="mt-4 inline-flex h-11 w-full items-center justify-center rounded-md bg-emerald-600 px-4 text-sm font-semibold text-white transition hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-slate-300"
                disabled={busy || !displayName.trim()}
                type="submit"
              >
                Приєднатися
              </button>
            </form>
          ) : null}

          {game && currentPlayer ? (
            <section className="rounded-md border border-slate-200 bg-white p-5">
              <h2 className="text-lg font-bold text-slate-950">
                Керування стартом
              </h2>
              <p className="mt-2 text-sm leading-6 text-slate-600">
                Старт доступний власнику лобі, коли приєднано від 2 до 6
                гравців.
              </p>
              <button
                className="mt-4 inline-flex h-11 w-full items-center justify-center rounded-md bg-slate-950 px-4 text-sm font-semibold text-white transition hover:bg-slate-800 disabled:cursor-not-allowed disabled:bg-slate-300"
                disabled={busy || !canStart}
                onClick={handleStartGame}
                type="button"
              >
                {game.status === 'lobby' ? 'Почати гру' : 'Гру почато'}
              </button>
              {game.status !== 'lobby' ? (
                <Link
                  className="mt-3 inline-flex h-11 w-full items-center justify-center rounded-md bg-emerald-600 px-4 text-sm font-semibold text-white transition hover:bg-emerald-700"
                  href={`/play/${encodeURIComponent(game.join_code)}`}
                >
                  До гри
                </Link>
              ) : null}
              {game.status === 'lobby' ? (
                <button
                  className="mt-3 inline-flex h-11 w-full items-center justify-center rounded-md border border-rose-200 px-4 text-sm font-semibold text-rose-700 transition hover:bg-rose-50 disabled:cursor-not-allowed disabled:text-slate-300"
                  disabled={busy}
                  onClick={handleLeaveGame}
                  type="button"
                >
                  Вийти з лобі
                </button>
              ) : null}
              {!isOwner ? (
                <p className="mt-3 text-xs font-medium text-slate-500">
                  Почати гру може тільки власник сесії.
                </p>
              ) : null}
            </section>
          ) : null}
        </aside>
      </main>
    </div>
  );
}
