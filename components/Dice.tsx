'use client';

import { useMemo, useState } from 'react';

import { ensurePlayableUser, getSupabaseClient } from '@/lib/supabase';
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
  compact?: boolean;
  currentTurnPlayerId?: PlayerId | null;
  disabled?: boolean;
  gameId: GameId | null;
  isCurrentPlayerTurn?: boolean;
  onRolled?: (state?: GameState) => Promise<void> | void;
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

function DieFace({
  compact,
  rolling,
  value,
}: {
  compact?: boolean;
  rolling?: boolean;
  value: number | null;
}) {
  const activePips = value ? pipPositions[value] ?? [] : [];

  return (
    <div
      aria-label={value ? `Кубик: ${value}` : 'Кубик не кинуто'}
      className={joinClassNames(
        'neo-panel-pressed grid shrink-0 grid-cols-3 grid-rows-3 rounded-[16px] border border-slate-300 bg-white shadow-sm',
        compact ? 'h-14 w-14 gap-0.5 p-2' : 'h-20 w-20 gap-1 p-3',
        rolling && 'neo-dice-rolling',
      )}
      role="img"
    >
      {Array.from({ length: 9 }, (_, index) => {
        const position = index + 1;

        return (
          <span
            className={joinClassNames(
              'self-center justify-self-center rounded-full',
              compact ? 'h-2.5 w-2.5' : 'h-3 w-3',
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
  compact,
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
      await ensurePlayableUser();

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
      const message = readErrorMessage(caughtError);

      setError(
        message === 'not_your_turn'
          ? 'Хід вже перейшов іншому гравцю. Оновлюємо стан...'
          : message,
      );

      if (
        message === 'not_your_turn' ||
        message === 'pending_action_must_be_resolved'
      ) {
        await onRolled?.();
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <section
      aria-label="Кидок кубика"
      className={joinClassNames(
        'neo-panel rounded-[18px] border border-slate-200 bg-white shadow-sm',
        compact ? 'p-2' : 'p-4',
        className,
      )}
    >
      <div className={joinClassNames('flex items-center', compact ? 'gap-2' : 'gap-4')}>
        <DieFace compact={compact} rolling={busy} value={lastRoll?.die ?? null} />

        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <h2
              className={joinClassNames(
                'font-bold tracking-normal text-slate-950',
                compact ? 'text-sm' : 'text-lg',
              )}
            >
              Кубик
            </h2>
            {lastRoll?.skipped ? (
              <span className="rounded bg-blue-100 px-2 py-1 text-xs font-bold text-blue-800">
                Хід пропущено
              </span>
            ) : null}
          </div>

          <p
            className={joinClassNames(
              'text-slate-600',
              compact
                ? 'mt-1 truncate text-[11px] font-semibold leading-4'
                : 'mt-2 text-sm leading-6',
            )}
            aria-live="polite"
          >
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
        className={joinClassNames(
          'inline-flex w-full items-center justify-center rounded-[16px] bg-slate-950 font-semibold text-white transition hover:bg-slate-800 disabled:cursor-not-allowed disabled:bg-slate-300',
          'neo-button',
          compact ? 'mt-2 h-9 px-3 text-xs' : 'mt-4 h-11 px-4 text-sm',
        )}
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
