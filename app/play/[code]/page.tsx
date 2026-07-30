'use client';

import Link from 'next/link';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import Board from '@/components/Board';
import AuthButton from '@/components/AuthButton';
import ConnectionStatus from '@/components/ConnectionStatus';
import Dice from '@/components/Dice';
import GameLog from '@/components/GameLog';
import PlayerCard from '@/components/PlayerCard';
import { useGameRealtime } from '@/hooks/useGameRealtime';
import { getSupabaseClient, requireAuthenticatedUser } from '@/lib/supabase';
import type { GameState, PendingAction, Player, PlayerId } from '@/types';

type PlayPageProps = {
  params: {
    code: string;
  };
};

type RpcArgs = Record<string, number | string | null>;

const statusLabels: Record<GameState['status'], string> = {
  finished: 'Завершена',
  in_progress: 'Триває',
  lobby: 'Лобі',
};

const pendingActionLabels: Record<PendingAction['type'], string> = {
  advertising_offer: 'Реклама',
  casino_bet: 'Казино',
  ceo_election: 'Вибори CEO',
  client_decision: 'Клієнт',
  client_stock_choice: 'Продаж запасу',
  company_share_purchase: 'Купівля акцій',
  deal_decision: 'Угода',
  image_offer: 'Імідж',
  outer_ring_choice: 'Перехід кола',
  tender_purchase: 'Тендер',
};

const currencyFormatter = new Intl.NumberFormat('uk-UA', {
  currency: 'USD',
  maximumFractionDigits: 0,
  style: 'currency',
});

const integerFormatter = new Intl.NumberFormat('uk-UA', {
  maximumFractionDigits: 0,
});

function joinClassNames(...classes: Array<string | false | null | undefined>) {
  return classes.filter(Boolean).join(' ');
}

function normalizeJoinCode(value: string) {
  return decodeURIComponent(value).trim().toUpperCase();
}

function formatMoney(value: number) {
  return currencyFormatter.format(value);
}

function formatInteger(value: number) {
  return integerFormatter.format(value);
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

function readPayloadValue(payload: Record<string, unknown>, key: string) {
  const value = payload[key];

  if (typeof value === 'number' || typeof value === 'string') {
    return String(value);
  }

  if (typeof value === 'boolean') {
    return value ? 'Так' : 'Ні';
  }

  return null;
}

function buildActionDetails(action: PendingAction) {
  const detailKeys = [
    ['cellId', action.cellId ?? null],
    ['income', readPayloadValue(action.payload, 'income')],
    ['importance', readPayloadValue(action.payload, 'importance')],
    ['price', readPayloadValue(action.payload, 'price')],
    ['buyout', readPayloadValue(action.payload, 'buyout')],
    ['sharePrice', readPayloadValue(action.payload, 'sharePrice')],
    ['availableShares', readPayloadValue(action.payload, 'availableShares')],
    ['relationship', readPayloadValue(action.payload, 'relationship')],
    ['successfulDeals', readPayloadValue(action.payload, 'successfulDeals')],
    ['balance', readPayloadValue(action.payload, 'balance')],
    ['targetCellId', readPayloadValue(action.payload, 'targetCellId')],
  ];

  return detailKeys
    .filter(([, value]) => Boolean(value))
    .slice(0, 5) as Array<[string, string]>;
}

function SeatSwitcher({
  activePlayerId,
  browserPlayerId,
  currentTurnPlayerId,
  onSelect,
  players,
}: {
  activePlayerId: PlayerId | null;
  browserPlayerId: PlayerId | null;
  currentTurnPlayerId: PlayerId | null;
  onSelect: (playerId: PlayerId) => void;
  players: Player[];
}) {
  return (
    <div className="flex gap-2 overflow-x-auto pb-1">
      {players.map((player) => {
        const isActive = player.id === activePlayerId;
        const isTurn = player.id === currentTurnPlayerId;
        const isBrowserPlayer = player.id === browserPlayerId;

        return (
          <button
            aria-pressed={isActive}
            className={joinClassNames(
              'min-w-36 rounded-md border px-3 py-2 text-left transition',
              isActive
                ? 'border-emerald-500 bg-emerald-50 text-emerald-950 ring-2 ring-emerald-100'
                : 'border-slate-200 bg-white text-slate-700 hover:border-slate-300 hover:bg-slate-50',
            )}
            key={player.id}
            onClick={() => onSelect(player.id)}
            type="button"
          >
            <span className="block truncate text-sm font-bold">
              {player.name}
            </span>
            <span className="mt-1 flex flex-wrap gap-1">
              <span className="rounded bg-slate-100 px-1.5 py-0.5 text-[11px] font-bold text-slate-600">
                Місце {player.seatNumber}
              </span>
              {isTurn ? (
                <span className="rounded bg-blue-100 px-1.5 py-0.5 text-[11px] font-bold text-blue-700">
                  Хід
                </span>
              ) : null}
              {isBrowserPlayer ? (
                <span className="rounded bg-slate-950 px-1.5 py-0.5 text-[11px] font-bold text-white">
                  Ви
                </span>
              ) : null}
            </span>
          </button>
        );
      })}
    </div>
  );
}

function PendingActionPanel({
  action,
  activePlayer,
  controllablePlayerId,
  gameState,
  onResolved,
}: {
  action: PendingAction | null;
  activePlayer: Player | null;
  controllablePlayerId: PlayerId | null;
  gameState: GameState;
  onResolved: () => Promise<void>;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [shareCount, setShareCount] = useState(1);
  const [stockToSell, setStockToSell] = useState(1);

  const isActiveAction = Boolean(
    action &&
      activePlayer &&
      action.playerId === activePlayer.id &&
      gameState.currentTurnPlayerId === activePlayer.id &&
      gameState.status === 'in_progress',
  );
  const canAct = Boolean(
    isActiveAction && activePlayer && activePlayer.id === controllablePlayerId,
  );

  const runRpc = useCallback(
    async (rpcName: string, args: RpcArgs) => {
      setBusy(true);
      setError(null);

      try {
        await requireAuthenticatedUser();

        const supabase = getSupabaseClient();
        const { error: rpcError } = await supabase.rpc(rpcName, args);

        if (rpcError) {
          throw rpcError;
        }

        await onResolved();
      } catch (caughtError) {
        setError(readErrorMessage(caughtError));
      } finally {
        setBusy(false);
      }
    },
    [onResolved],
  );

  if (!action) {
    return (
      <section className="rounded-md border border-slate-200 bg-white p-4 shadow-sm">
        <div className="flex items-center justify-between gap-3">
          <h2 className="text-base font-bold tracking-normal text-slate-950">
            Дія
          </h2>
          <span className="rounded bg-slate-100 px-2 py-1 text-xs font-bold text-slate-600">
            Немає
          </span>
        </div>
      </section>
    );
  }

  const details = buildActionDetails(action);

  return (
    <section className="rounded-md border border-slate-200 bg-white p-4 shadow-sm">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-xs font-semibold uppercase tracking-normal text-slate-500">
            Очікує рішення
          </p>
          <h2 className="mt-1 truncate text-base font-bold tracking-normal text-slate-950">
            {pendingActionLabels[action.type]}
          </h2>
        </div>
        <span
          className={joinClassNames(
            'shrink-0 rounded px-2 py-1 text-xs font-bold',
            canAct
              ? 'bg-emerald-100 text-emerald-800'
              : 'bg-slate-100 text-slate-600',
          )}
        >
          {canAct ? 'Активно' : isActiveAction ? 'Перегляд' : 'Інше сидіння'}
        </span>
      </div>

      {details.length > 0 ? (
        <dl className="mt-3 grid grid-cols-2 gap-2">
          {details.map(([label, value]) => (
            <div className="min-w-0 rounded bg-slate-50 px-2 py-1" key={label}>
              <dt className="truncate text-[11px] font-bold text-slate-500">
                {label}
              </dt>
              <dd className="truncate text-xs font-semibold text-slate-800">
                {value}
              </dd>
            </div>
          ))}
        </dl>
      ) : null}

      <div className="mt-4 space-y-2">
        {action.type === 'deal_decision' ? (
          <div className="grid grid-cols-2 gap-2">
            <button
              className="h-10 rounded-md bg-emerald-600 px-3 text-sm font-semibold text-white transition hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-slate-300"
              disabled={!canAct || busy}
              onClick={() =>
                runRpc('resolve_deal', {
                  p_decision: 'accept',
                  p_game_id: gameState.gameId,
                })
              }
              type="button"
            >
              Прийняти
            </button>
            <button
              className="h-10 rounded-md border border-slate-300 px-3 text-sm font-semibold text-slate-700 transition hover:bg-slate-50 disabled:cursor-not-allowed disabled:text-slate-300"
              disabled={!canAct || busy}
              onClick={() =>
                runRpc('resolve_deal', {
                  p_decision: 'decline',
                  p_game_id: gameState.gameId,
                })
              }
              type="button"
            >
              Відхилити
            </button>
          </div>
        ) : null}

        {action.type === 'client_decision' ? (
          <div className="grid grid-cols-2 gap-2">
            <button
              className="h-10 rounded-md bg-emerald-600 px-3 text-sm font-semibold text-white transition hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-slate-300"
              disabled={!canAct || busy}
              onClick={() =>
                runRpc('resolve_client', {
                  p_decision: 'accept',
                  p_game_id: gameState.gameId,
                  p_stock_to_sell: null,
                })
              }
              type="button"
            >
              Грати
            </button>
            <button
              className="h-10 rounded-md border border-slate-300 px-3 text-sm font-semibold text-slate-700 transition hover:bg-slate-50 disabled:cursor-not-allowed disabled:text-slate-300"
              disabled={!canAct || busy}
              onClick={() =>
                runRpc('resolve_client', {
                  p_decision: 'decline',
                  p_game_id: gameState.gameId,
                  p_stock_to_sell: null,
                })
              }
              type="button"
            >
              Відхилити
            </button>
          </div>
        ) : null}

        {action.type === 'client_stock_choice' ? (
          <div className="grid grid-cols-[minmax(0,1fr)_120px] gap-2">
            <input
              className="h-10 min-w-0 rounded-md border border-slate-300 px-3 text-sm font-semibold outline-none transition focus:border-emerald-600 focus:ring-4 focus:ring-emerald-100"
              min={0}
              onChange={(event) =>
                setStockToSell(Math.max(0, Number(event.target.value) || 0))
              }
              type="number"
              value={stockToSell}
            />
            <button
              className="h-10 rounded-md bg-slate-950 px-3 text-sm font-semibold text-white transition hover:bg-slate-800 disabled:cursor-not-allowed disabled:bg-slate-300"
              disabled={!canAct || busy}
              onClick={() =>
                runRpc('resolve_client', {
                  p_decision: null,
                  p_game_id: gameState.gameId,
                  p_stock_to_sell: stockToSell,
                })
              }
              type="button"
            >
              Продати
            </button>
          </div>
        ) : null}

        {action.type === 'tender_purchase' ? (
          <div className="grid grid-cols-2 gap-2">
            <button
              className="h-10 rounded-md bg-emerald-600 px-3 text-sm font-semibold text-white transition hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-slate-300"
              disabled={!canAct || busy}
              onClick={() =>
                runRpc('resolve_tender', {
                  p_decision: 'accept',
                  p_game_id: gameState.gameId,
                })
              }
              type="button"
            >
              Купити
            </button>
            <button
              className="h-10 rounded-md border border-slate-300 px-3 text-sm font-semibold text-slate-700 transition hover:bg-slate-50 disabled:cursor-not-allowed disabled:text-slate-300"
              disabled={!canAct || busy}
              onClick={() =>
                runRpc('resolve_tender', {
                  p_decision: 'decline',
                  p_game_id: gameState.gameId,
                })
              }
              type="button"
            >
              Пропустити
            </button>
          </div>
        ) : null}

        {action.type === 'company_share_purchase' ? (
          <div className="grid grid-cols-[minmax(0,1fr)_112px_112px] gap-2">
            <input
              className="h-10 min-w-0 rounded-md border border-slate-300 px-3 text-sm font-semibold outline-none transition focus:border-emerald-600 focus:ring-4 focus:ring-emerald-100"
              min={0}
              onChange={(event) =>
                setShareCount(Math.max(0, Number(event.target.value) || 0))
              }
              type="number"
              value={shareCount}
            />
            <button
              className="h-10 rounded-md bg-slate-950 px-3 text-sm font-semibold text-white transition hover:bg-slate-800 disabled:cursor-not-allowed disabled:bg-slate-300"
              disabled={!canAct || busy}
              onClick={() =>
                runRpc('resolve_company', {
                  p_game_id: gameState.gameId,
                  p_share_count: shareCount,
                })
              }
              type="button"
            >
              Купити
            </button>
            <button
              className="h-10 rounded-md border border-slate-300 px-3 text-sm font-semibold text-slate-700 transition hover:bg-slate-50 disabled:cursor-not-allowed disabled:text-slate-300"
              disabled={!canAct || busy}
              onClick={() =>
                runRpc('resolve_company', {
                  p_game_id: gameState.gameId,
                  p_share_count: 0,
                })
              }
              type="button"
            >
              0
            </button>
          </div>
        ) : null}

        {action.type === 'outer_ring_choice' ? (
          <div className="grid grid-cols-2 gap-2">
            <button
              className="h-10 rounded-md bg-emerald-600 px-3 text-sm font-semibold text-white transition hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-slate-300"
              disabled={!canAct || busy}
              onClick={() =>
                runRpc('ring_transition', {
                  p_decision: 'move_to_outer',
                  p_game_id: gameState.gameId,
                })
              }
              type="button"
            >
              Перейти
            </button>
            <button
              className="h-10 rounded-md border border-slate-300 px-3 text-sm font-semibold text-slate-700 transition hover:bg-slate-50 disabled:cursor-not-allowed disabled:text-slate-300"
              disabled={!canAct || busy}
              onClick={() =>
                runRpc('ring_transition', {
                  p_decision: 'stay_inner',
                  p_game_id: gameState.gameId,
                })
              }
              type="button"
            >
              Залишитись
            </button>
          </div>
        ) : null}

        {action.type === 'ceo_election' ? (
          <button
            className="h-10 w-full rounded-md bg-slate-950 px-3 text-sm font-semibold text-white transition hover:bg-slate-800 disabled:cursor-not-allowed disabled:bg-slate-300"
            disabled={!canAct || busy}
            onClick={() =>
              runRpc('elect_ceo', {
                p_game_id: gameState.gameId,
              })
            }
            type="button"
          >
            Провести вибори
          </button>
        ) : null}
      </div>

      {error ? (
        <p className="mt-3 text-sm font-semibold text-rose-700" aria-live="polite">
          {error}
        </p>
      ) : null}
    </section>
  );
}

export default function PlayPage({ params }: PlayPageProps) {
  const joinCode = useMemo(() => normalizeJoinCode(params.code), [params.code]);
  const botTurnInFlightRef = useRef<string | null>(null);
  const storageKey = useMemo(
    () => `economic-olympus-active-player:${joinCode}`,
    [joinCode],
  );
  const {
    currentPlayer,
    currentTurnPlayer,
    error,
    gameState,
    isBrowserOnline,
    isRealtimeConnected,
    lastSyncedAt,
    loading,
    players,
    realtimeStatus,
    refresh,
    refreshing,
  } = useGameRealtime({ joinCode });
  const [activePlayerId, setActivePlayerId] = useState<PlayerId | null>(null);
  const [botTurnError, setBotTurnError] = useState<string | null>(null);
  const [thinkingBotPlayerId, setThinkingBotPlayerId] =
    useState<PlayerId | null>(null);

  useEffect(() => {
    try {
      const savedPlayerId = window.sessionStorage.getItem(storageKey);

      if (savedPlayerId) {
        setActivePlayerId(savedPlayerId);
      }
    } catch {
      setActivePlayerId(null);
    }
  }, [storageKey]);

  useEffect(() => {
    setActivePlayerId((currentActivePlayerId) => {
      if (
        currentActivePlayerId &&
        players.some((player) => player.id === currentActivePlayerId)
      ) {
        return currentActivePlayerId;
      }

      return currentTurnPlayer?.id ?? currentPlayer?.id ?? players[0]?.id ?? null;
    });
  }, [currentPlayer?.id, currentTurnPlayer?.id, players]);

  const activePlayer = useMemo(
    () => players.find((player) => player.id === activePlayerId) ?? null,
    [activePlayerId, players],
  );
  const boardPlayers = useMemo(
    () =>
      players.map((player) => ({
        cellId: player.cellId,
        id: player.id,
        name: player.name,
      })),
    [players],
  );
  const activeCellId =
    activePlayer?.cellId ?? currentTurnPlayer?.cellId ?? players[0]?.cellId;
  const isActivePlayerTurn = Boolean(
    activePlayer && gameState?.currentTurnPlayerId === activePlayer.id,
  );
  const canControlActivePlayer = Boolean(
    activePlayer && currentPlayer && activePlayer.id === currentPlayer.id,
  );
  const diceDisabled =
    !gameState ||
    gameState.status !== 'in_progress' ||
    !isActivePlayerTurn ||
    !canControlActivePlayer ||
    Boolean(gameState.pendingAction);

  useEffect(() => {
    if (
      !gameState ||
      gameState.status !== 'in_progress' ||
      !currentTurnPlayer?.isBot
    ) {
      setThinkingBotPlayerId(null);
      return;
    }

    const pendingActionKey = gameState.pendingAction?.id ?? 'roll';
    const gameId = gameState.gameId;
    const botPlayerId = currentTurnPlayer.id;
    const turnKey = [
      gameId,
      botPlayerId,
      gameState.turn?.number ?? 0,
      pendingActionKey,
    ].join(':');

    if (botTurnInFlightRef.current === turnKey) {
      return;
    }

    setBotTurnError(null);
    setThinkingBotPlayerId(currentTurnPlayer.id);

    const delay = 1200 + Math.floor(Math.random() * 801);
    const timeoutId = window.setTimeout(() => {
      botTurnInFlightRef.current = turnKey;

      async function resolveBotTurn() {
        try {
          const supabase = getSupabaseClient();
          const { error: botError } = await supabase.rpc('resolve_bot_turn', {
            p_game_id: gameId,
          });

          if (botError) {
            throw botError;
          }

          await refresh();
        } catch (caughtError) {
          setBotTurnError(readErrorMessage(caughtError));
        } finally {
          if (botTurnInFlightRef.current === turnKey) {
            botTurnInFlightRef.current = null;
          }

          setThinkingBotPlayerId((playerId) =>
            playerId === botPlayerId ? null : playerId,
          );
        }
      }

      void resolveBotTurn();
    }, delay);

    return () => {
      window.clearTimeout(timeoutId);
    };
  }, [
    currentTurnPlayer?.id,
    currentTurnPlayer?.isBot,
    gameState?.gameId,
    gameState?.pendingAction?.id,
    gameState?.status,
    gameState?.turn?.number,
    refresh,
  ]);

  const selectActivePlayer = useCallback(
    (playerId: PlayerId) => {
      setActivePlayerId(playerId);

      try {
        window.sessionStorage.setItem(storageKey, playerId);
      } catch {
        // Session storage is optional; the active seat still works in memory.
      }
    },
    [storageKey],
  );

  return (
    <div className="min-h-screen bg-slate-50 text-slate-950">
      <header className="border-b border-slate-200 bg-white shadow-sm">
        <div className="mx-auto flex w-full max-w-[1600px] items-center justify-between gap-4 px-4 py-4 sm:px-6">
          <Link className="text-lg font-semibold tracking-normal" href="/">
            Економічна Монополія
          </Link>
          <nav className="flex items-center gap-3 text-sm font-medium text-slate-600">
            <Link className="transition hover:text-slate-950" href="/rules">
              Правила
            </Link>
            <Link
              className="rounded-md border border-slate-300 px-3 py-2 transition hover:bg-slate-50"
              href={`/lobby/${encodeURIComponent(joinCode)}`}
            >
              Лобі
            </Link>
            <AuthButton />
          </nav>
        </div>
      </header>

      <main className="mx-auto w-full max-w-[1600px] px-4 py-6 sm:px-6">
        {loading ? (
          <section className="rounded-md border border-slate-200 bg-white p-6 shadow-sm">
            <p className="text-sm font-semibold text-slate-600">
              Завантажуємо гру...
            </p>
          </section>
        ) : null}

        {error ? (
          <section className="rounded-md border border-rose-200 bg-rose-50 p-5 text-sm font-semibold text-rose-800">
            {error}
          </section>
        ) : null}

        {!loading && !gameState ? (
          <section className="rounded-md border border-slate-200 bg-white p-6 shadow-sm">
            <h1 className="text-2xl font-bold tracking-normal text-slate-950">
              Гру не знайдено
            </h1>
            <Link
              className="mt-5 inline-flex h-10 items-center justify-center rounded-md bg-slate-950 px-4 text-sm font-semibold text-white transition hover:bg-slate-800"
              href="/#start"
            >
              На головну
            </Link>
          </section>
        ) : null}

        {gameState ? (
          <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_390px]">
            <div className="min-w-0 space-y-4">
              <section className="rounded-md border border-slate-200 bg-white p-4 shadow-sm">
                <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                  <div className="min-w-0">
                    <p className="text-xs font-semibold uppercase tracking-normal text-emerald-700">
                      Код {gameState.joinCode}
                    </p>
                    <h1 className="mt-1 truncate text-2xl font-bold tracking-normal text-slate-950">
                      Ігровий стіл
                    </h1>
                  </div>
                  <div className="grid grid-cols-3 gap-2 text-center sm:min-w-[360px]">
                    <div className="rounded-md bg-slate-50 px-3 py-2">
                      <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                        Статус
                      </p>
                      <p className="mt-1 truncate text-sm font-bold text-slate-950">
                        {statusLabels[gameState.status]}
                      </p>
                    </div>
                    <div className="rounded-md bg-slate-50 px-3 py-2">
                      <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                        Гравці
                      </p>
                      <p className="mt-1 text-sm font-bold text-slate-950">
                        {players.length}/{gameState.maxPlayers}
                      </p>
                    </div>
                    <div className="rounded-md bg-slate-50 px-3 py-2">
                      <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                        Realtime
                      </p>
                      <p
                        className={joinClassNames(
                          'mt-1 truncate text-sm font-bold',
                          isRealtimeConnected ? 'text-emerald-700' : 'text-amber-700',
                        )}
                      >
                        {isRealtimeConnected ? 'Online' : 'Sync'}
                      </p>
                    </div>
                  </div>
                </div>

                {players.length > 0 ? (
                  <div className="mt-4 border-t border-slate-200 pt-4">
                    <SeatSwitcher
                      activePlayerId={activePlayer?.id ?? null}
                      browserPlayerId={currentPlayer?.id ?? null}
                      currentTurnPlayerId={gameState.currentTurnPlayerId}
                      onSelect={selectActivePlayer}
                      players={players}
                    />
                  </div>
                ) : null}
              </section>

              <ConnectionStatus
                isOnline={isBrowserOnline}
                lastSyncedAt={lastSyncedAt}
                onRefresh={refresh}
                realtimeStatus={realtimeStatus}
                refreshing={refreshing}
              />

              {gameState.status === 'lobby' ? (
                <section className="rounded-md border border-amber-200 bg-amber-50 p-4 text-sm font-semibold text-amber-900">
                  Гра ще в лобі. Почати можна зі сторінки лобі.
                </section>
              ) : null}

              {gameState.status === 'finished' ? (
                <section className="rounded-md border border-emerald-200 bg-emerald-50 p-4 text-sm font-semibold text-emerald-900">
                  Переможець:{' '}
                  {players.find((player) => player.id === gameState.winnerPlayerId)
                    ?.name ?? 'очікується'}
                </section>
              ) : null}

              <Board
                activeCellId={activeCellId}
                centerSlot={
                  <div className="min-w-0">
                    <p className="text-xs font-semibold uppercase tracking-normal text-slate-500">
                      Зараз ходить
                    </p>
                    <p className="mt-1 truncate text-sm font-bold text-slate-950">
                      {currentTurnPlayer?.name ?? 'очікується'}
                    </p>
                    {currentTurnPlayer?.isBot ? (
                      <p className="mt-2 truncate text-xs font-semibold text-amber-700">
                        {thinkingBotPlayerId === currentTurnPlayer.id
                          ? 'Бот думає...'
                          : 'Автохід бота'}
                      </p>
                    ) : null}
                    {activePlayer ? (
                      <p className="mt-2 truncate text-xs font-semibold text-emerald-700">
                        Активне сидіння: {activePlayer.name}
                      </p>
                    ) : null}
                  </div>
                }
                players={boardPlayers}
              />

              {players.length > 0 ? (
                <section className="grid gap-4 lg:grid-cols-2 2xl:grid-cols-3">
                  {players.map((player) => (
                    <PlayerCard
                      gameState={gameState}
                      isCurrentTurn={player.id === gameState.currentTurnPlayerId}
                      isCurrentUser={player.id === currentPlayer?.id}
                      key={player.id}
                      player={player}
                    />
                  ))}
                </section>
              ) : null}
            </div>

            <aside className="space-y-4 xl:sticky xl:top-4 xl:max-h-[calc(100vh-2rem)] xl:overflow-y-auto">
              <Dice
                currentTurnPlayerId={gameState.currentTurnPlayerId}
                disabled={diceDisabled}
                gameId={gameState.gameId}
                isCurrentPlayerTurn={isActivePlayerTurn}
                onRolled={refresh}
                playerId={activePlayer?.id ?? null}
              />

              {activePlayer ? (
                <section className="rounded-md border border-slate-200 bg-white p-4 shadow-sm">
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <p className="text-xs font-semibold uppercase tracking-normal text-slate-500">
                        Активне сидіння
                      </p>
                      <h2 className="mt-1 truncate text-lg font-bold tracking-normal text-slate-950">
                        {activePlayer.name}
                      </h2>
                    </div>
                    <span
                      className={joinClassNames(
                        'rounded px-2 py-1 text-xs font-bold',
                        !canControlActivePlayer
                          ? 'bg-amber-100 text-amber-800'
                          : isActivePlayerTurn
                          ? 'bg-blue-100 text-blue-800'
                          : 'bg-slate-100 text-slate-600',
                      )}
                    >
                      {!canControlActivePlayer
                        ? 'Перегляд'
                        : isActivePlayerTurn
                          ? 'Хід'
                          : activePlayer.ring}
                    </span>
                  </div>
                  <div className="mt-4 grid grid-cols-3 gap-2 text-center">
                    <div className="rounded bg-slate-50 px-2 py-2">
                      <p className="text-[11px] font-bold text-slate-500">Баланс</p>
                      <p className="mt-1 truncate text-sm font-bold text-slate-950">
                        {formatMoney(activePlayer.balance)}
                      </p>
                    </div>
                    <div className="rounded bg-slate-50 px-2 py-2">
                      <p className="text-[11px] font-bold text-slate-500">Імідж</p>
                      <p className="mt-1 text-sm font-bold text-slate-950">
                        {formatInteger(activePlayer.image)}
                      </p>
                    </div>
                    <div className="rounded bg-slate-50 px-2 py-2">
                      <p className="text-[11px] font-bold text-slate-500">Запас</p>
                      <p className="mt-1 text-sm font-bold text-slate-950">
                        {formatInteger(activePlayer.inventory)}
                      </p>
                    </div>
                  </div>
                  {!canControlActivePlayer ? (
                    <p className="mt-3 rounded-md bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
                      Це сидіння відкрите для перегляду.
                    </p>
                  ) : null}
                </section>
              ) : null}

              <PendingActionPanel
                action={gameState.pendingAction}
                activePlayer={activePlayer}
                controllablePlayerId={currentPlayer?.id ?? null}
                gameState={gameState}
                onResolved={refresh}
              />

              {thinkingBotPlayerId || botTurnError ? (
                <section className="rounded-md border border-amber-200 bg-amber-50 p-4 text-sm font-semibold text-amber-900">
                  {botTurnError
                    ? `Помилка ходу бота: ${botTurnError}`
                    : 'Бот думає над ходом...'}
                </section>
              ) : null}

              <GameLog
                className="max-h-[520px]"
                entries={gameState.log}
                loading={refreshing}
                players={players}
              />
            </aside>
          </div>
        ) : null}
      </main>
    </div>
  );
}
