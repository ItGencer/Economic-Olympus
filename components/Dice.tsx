'use client';

import { useMemo, useState } from 'react';

import { getSupabaseClient, requireAuthenticatedUser } from '@/lib/supabase';
import type { CellId, GameId, GameState, PlayerId } from '@/types';

type RollDiceResult = {
  die: number | null;
  from_cell_id: CellId;
  next_player_id: PlayerId;
  player_id: PlayerId;
  skipped: boolean;
  state: GameState;
  to_cell_id: CellId;
};

type LastRoll = {
  die: number | null;
  fromCellId: CellId;
  skipped: boolean;
  toCellId: CellId;
};

type DiceProps = {
  className?: string;
  currentTurnPlayerId?: PlayerId | null;
  disabled?: boolean;
  gameId: GameId | null;
  isCurrentPlayerTurn?: boolean;
  onRolled?: (state: GameState) => Promise<void> | void;
  playerId?: PlayerId | null;
};

const pipPositions: Record<number, number[]> = {
  1: [5],
  2: [1, 9],
  3: [1, 5, 9],
  4: [1, 3, 7, 9],
  5: [1, 3, 5, 7, 9],
  6: [1, 3, 4, 6, 7, 9],
};

function joinClassNames(...classes: Array<string | false | undefined>) {
  return classes.filter(Boolean).join(' ');
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function readErrorMessage(error: unknown) {
  if (error instanceof Error) {
    return error.message;
  }

  if (isRecord(error) && typeof error.message === 'string') {
    return error.message;
  }

  return 'Невідома помилка';
}

function isRollDiceResult(value: unknown): value is RollDiceResult {
  return (
    isRecord(value) &&
    typeof value.from_cell_id === 'string' &&
    typeof value.next_player_id === 'string' &&
    typeof value.player_id === 'string' &&
    typeof value.skipped === 'boolean' &&
    isRecord(value.state) &&
    typeof value.to_cell_id === 'string' &&
    (typeof value.die === 'number' || value.die === null)
  );
}

function DieFace({ value }: { value: number | null }) {
  const activePips = value ? pipPositions[value] ?? [] : [];

  return (
    <div
      aria-label={value ? `Кубик: ${value}` : 'Кубик не кинуто'}
      className="grid h-20 w-20 shrink-0 grid-cols-3 grid-rows-3 gap-1 rounded-md border border-slate-300 bg-white p-3 shadow-sm"
      role="img"
    >
      {Array.from({ length: 9 }, (_, index) => {
        const position = index + 1;

        return (
          <span
            className={joinClassNames(
              'h-3 w-3 self-center justify-self-center rounded-full',
              activePips.includes(position) ? 'bg-slate-950' : 'bg-transparent',
            )}
            key={position}
          />
        );
      })}
    </div>
  );
}

export function Dice({
  className,
  currentTurnPlayerId,
  disabled,
  gameId,
  isCurrentPlayerTurn,
  onRolled,
  playerId,
}: DiceProps) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lastRoll, setLastRoll] = useState<LastRoll | null>(null);

  const turnIsKnown =
    typeof isCurrentPlayerTurn === 'boolean' ||
    (Boolean(playerId) && Boolean(currentTurnPlayerId));
  const canRoll = useMemo(() => {
    const isTurn =
      isCurrentPlayerTurn ??
      (playerId && currentTurnPlayerId ? playerId === currentTurnPlayerId : true);

    return Boolean(gameId && isTurn && !busy && !disabled);
  }, [busy, currentTurnPlayerId, disabled, gameId, isCurrentPlayerTurn, playerId]);

  async function handleRollDice() {
    if (!gameId || !canRoll) {
      return;
    }

    setBusy(true);
    setError(null);

    try {
      await requireAuthenticatedUser();

      const supabase = getSupabaseClient();
      const { data, error: rollError } = await supabase.rpc('roll_dice', {
        p_game_id: gameId,
      });

      if (rollError) {
        throw rollError;
      }

      if (!isRollDiceResult(data)) {
        throw new Error('RPC roll_dice returned an unexpected response.');
      }

      setLastRoll({
        die: data.die,
        fromCellId: data.from_cell_id,
        skipped: data.skipped,
        toCellId: data.to_cell_id,
      });

      await onRolled?.(data.state);
    } catch (caughtError) {
      setError(readErrorMessage(caughtError));
    } finally {
      setBusy(false);
    }
  }

  return (
    <section
      aria-label="Кидок кубика"
      className={joinClassNames(
        'rounded-md border border-slate-200 bg-white p-4 shadow-sm',
        className,
      )}
    >
      <div className="flex items-center gap-4">
        <DieFace value={lastRoll?.die ?? null} />

        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <h2 className="text-lg font-bold tracking-normal text-slate-950">
              Кубик
            </h2>
            {lastRoll?.skipped ? (
              <span className="rounded bg-blue-100 px-2 py-1 text-xs font-bold text-blue-800">
                Хід пропущено
              </span>
            ) : null}
          </div>

          <p className="mt-2 text-sm leading-6 text-slate-600" aria-live="polite">
            {lastRoll
              ? `${lastRoll.fromCellId} → ${lastRoll.toCellId}`
              : turnIsKnown && !canRoll && !busy
                ? 'Очікуємо хід іншого гравця'
                : 'Готово до кидка'}
          </p>

          {error ? (
            <p className="mt-2 text-sm font-semibold text-rose-700" aria-live="polite">
              {error}
            </p>
          ) : null}
        </div>
      </div>

      <button
        className="mt-4 inline-flex h-11 w-full items-center justify-center rounded-md bg-slate-950 px-4 text-sm font-semibold text-white transition hover:bg-slate-800 disabled:cursor-not-allowed disabled:bg-slate-300"
        disabled={!canRoll}
        onClick={handleRollDice}
        type="button"
      >
        {busy ? 'Кидаємо...' : 'Кинути кубик'}
      </button>
    </section>
  );
}

export default Dice;
