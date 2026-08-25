'use client';

import type { GameLogEntry, Player, PlayerId } from '@/types';

type GameLogProps = {
  className?: string;
  entries?: GameLogEntry[];
  loading?: boolean;
  maxVisible?: number;
  players?: Player[];
};

type EventTone = 'blue' | 'emerald' | 'rose' | 'amber' | 'violet' | 'slate';

type EventMeta = {
  label: string;
  tone: EventTone;
};

const eventMetaByType: Record<string, EventMeta> = {
  cell_advertising_pending: { label: 'Реклама', tone: 'amber' },
  cell_casino_pending: { label: 'Казино', tone: 'violet' },
  cell_client_pending: { label: 'Клієнт', tone: 'blue' },
  cell_company_pending: { label: 'Компанія', tone: 'blue' },
  cell_deal_pending: { label: 'Ділова зустріч', tone: 'amber' },
  cell_director: { label: 'Директор', tone: 'violet' },
  cell_image_pending: { label: 'Імідж', tone: 'blue' },
  cell_negative_reputation_pending: { label: 'Негативна репутація', tone: 'rose' },
  cell_random_pending: { label: 'Random', tone: 'amber' },
  cell_random: { label: 'Випадок', tone: 'violet' },
  cell_reputation: { label: 'Репутація', tone: 'blue' },
  cell_salary_pending: { label: 'Зарплата', tone: 'emerald' },
  cell_salary: { label: 'Дохід', tone: 'emerald' },
  cell_start: { label: 'Старт', tone: 'emerald' },
  cell_tax: { label: 'Податок', tone: 'rose' },
  cell_tender_pending: { label: 'Тендер', tone: 'amber' },
  cell_vacation: { label: 'Відпустка', tone: 'blue' },
  ceo_election_failed: { label: 'CEO', tone: 'rose' },
  ceo_election_won: { label: 'CEO', tone: 'emerald' },
  casino_declined: { label: 'Казино', tone: 'slate' },
  casino_lost: { label: 'Казино', tone: 'rose' },
  casino_won: { label: 'Казино', tone: 'emerald' },
  advertising_declined: { label: 'Реклама', tone: 'slate' },
  advertising_purchased: { label: 'Реклама', tone: 'emerald' },
  client_declined: { label: 'Клієнт', tone: 'slate' },
  client_scores_rolled: { label: 'Клієнт', tone: 'blue' },
  client_stock_sold: { label: 'Клієнт', tone: 'emerald' },
  company_purchase_skipped: { label: 'Компанія', tone: 'slate' },
  company_shares_purchased: { label: 'Акції', tone: 'emerald' },
  company_sold_out: { label: 'Компанія', tone: 'violet' },
  deal_declined: { label: 'Ділова зустріч', tone: 'slate' },
  deal_failed: { label: 'Ділова зустріч', tone: 'rose' },
  deal_successful: { label: 'Ділова зустріч', tone: 'emerald' },
  debt_locked: { label: 'Борг', tone: 'rose' },
  debt_unlocked: { label: 'Борг', tone: 'emerald' },
  debt_warning: { label: 'Борг', tone: 'amber' },
  director_no_change: { label: 'Директор', tone: 'slate' },
  directors_elected: { label: 'Директор', tone: 'emerald' },
  dice_rolled: { label: 'Кубик', tone: 'blue' },
  game_started: { label: 'Гра', tone: 'emerald' },
  game_ended_manually: { label: 'Гра', tone: 'rose' },
  game_won_by_elimination: { label: 'Перемога', tone: 'emerald' },
  image_declined: { label: 'Імідж', tone: 'slate' },
  image_purchased: { label: 'Імідж', tone: 'emerald' },
  negative_reputation_applied: { label: 'Негативна репутація', tone: 'rose' },
  outer_ring_choice_pending: { label: 'Зовнішнє коло', tone: 'amber' },
  outer_ring_moved: { label: 'Зовнішнє коло', tone: 'emerald' },
  outer_ring_stayed: { label: 'Зовнішнє коло', tone: 'slate' },
  player_eliminated: { label: 'Вибування', tone: 'rose' },
  random_event_applied: { label: 'Random', tone: 'violet' },
  salary_resolved: { label: 'Зарплата', tone: 'emerald' },
  start_bonus: { label: 'Start', tone: 'emerald' },
  tender_declined: { label: 'Тендер', tone: 'slate' },
  tender_fee_paid: { label: 'Тендер', tone: 'rose' },
  tender_owner_landed: { label: 'Тендер', tone: 'blue' },
  tender_purchased: { label: 'Тендер', tone: 'emerald' },
  turn_skipped: { label: 'Хід', tone: 'blue' },
};

const toneClasses: Record<EventTone, string> = {
  amber: 'border-amber-300/35 bg-amber-400/12 text-amber-100',
  blue: 'border-cyan-300/35 bg-cyan-400/12 text-cyan-100',
  emerald: 'border-emerald-300/35 bg-emerald-400/12 text-emerald-100',
  rose: 'border-rose-300/35 bg-rose-400/12 text-rose-100',
  slate: 'border-slate-300/25 bg-slate-300/10 text-slate-200',
  violet: 'border-violet-300/45 bg-violet-500/18 text-fuchsia-100',
};

const payloadLabels: Record<string, string> = {
  salaryDie: 'd20',
  salaryKind: 'Тип зарплати',
  salaryUnit: 'Множник',
  image: 'Імідж',
  amount: 'Сума',
  activePlayers: 'Активні',
  balanceAfter: 'Баланс',
  balanceDelta: 'Зміна балансу',
  balance: 'Баланс',
  betAmount: 'Ставка',
  cell_id: 'Клітинка',
  cell_type: 'Тип',
  coefficient: 'Коефіцієнт',
  debt: 'Борг',
  debt_locked: 'Борг',
  difference: 'Різниця',
  decision: 'Вибір',
  die: 'Кубик',
  dice: 'Кубики',
  income: 'Дохід',
  imageGain: 'Імідж',
  imageAfter: 'Імідж після',
  imageBefore: 'Імідж до',
  imageDelta: 'Зміна іміджу',
  imageLoss: 'Втрата іміджу',
  kind: 'Тип',
  multiplier: 'Множник',
  parity: 'Прогноз',
  passedStart: 'Пройшов Start',
  payout: 'Виплата',
  price: 'Ціна',
  releasedShares: 'Акції в банк',
  startBonus: 'Бонус Start',
  share_count: 'Акції',
  successful: 'Успіх',
  supportPercent: 'Підтримка',
  sign: 'Тип',
  score: 'Score',
  total: 'Сума',
  unit: 'Множник',
  unitPrice: 'Ціна за 1',
  to_cell_id: 'Куди',
  warningLimit: 'Ліміт',
  won: 'Виграш',
  variantKey: 'Картка',
  winnerName: 'Переможець',
  winnerPlayerId: 'Переможець',
};

const payloadKeys = Object.keys(payloadLabels);

const timeFormatter = new Intl.DateTimeFormat('uk-UA', {
  hour: '2-digit',
  minute: '2-digit',
});

function joinClassNames(...classes: Array<string | false | undefined>) {
  return classes.filter(Boolean).join(' ');
}

function getEventMeta(eventType: string): EventMeta {
  return eventMetaByType[eventType] ?? { label: eventType.replaceAll('_', ' '), tone: 'slate' };
}

function getPlayerNames(players: Player[]) {
  return players.reduce<Record<PlayerId, string>>((names, player) => {
    names[player.id] = player.name;

    return names;
  }, {});
}

function formatTime(value: string) {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return '';
  }

  return timeFormatter.format(date);
}

function formatPayloadValue(value: unknown) {
  if (Array.isArray(value)) {
    const items = value
      .map((item) =>
        typeof item === 'number' || typeof item === 'string' ? String(item) : null,
      )
      .filter(Boolean);

    return items.length > 0 ? items.join(' + ') : null;
  }

  if (typeof value === 'boolean') {
    return value ? 'Так' : 'Ні';
  }

  if (typeof value === 'number' || typeof value === 'string') {
    return String(value);
  }

  return null;
}

function getPayloadItems(payload: Record<string, unknown>) {
  return payloadKeys
    .map((key) => {
      const value = formatPayloadValue(payload[key]);

      return value ? { key, value } : null;
    })
    .filter((item): item is { key: string; value: string } => Boolean(item))
    .slice(0, 5);
}

export function GameLog({
  className,
  entries = [],
  loading = false,
  maxVisible = 40,
  players = [],
}: GameLogProps) {
  const playerNames = getPlayerNames(players);
  const visibleEntries = entries.slice(-maxVisible).reverse();

  return (
    <aside
      aria-label="Історія ходів"
      className={joinClassNames(
        'neo-panel flex min-h-0 flex-col rounded-[18px] border border-slate-200 bg-white shadow-sm',
        className,
      )}
    >
      <div className="flex items-center justify-between gap-3 border-b border-slate-200 px-4 py-3">
        <h2 className="text-base font-bold tracking-normal text-slate-950">
          Історія
        </h2>
        <span className="shrink-0 text-xs font-semibold text-slate-500">
          {entries.length}
        </span>
      </div>

      {loading ? (
        <div className="space-y-3 p-4" aria-hidden="true">
          {Array.from({ length: 5 }, (_, index) => (
            <div className="animate-pulse rounded-[16px] bg-violet-500/10 p-3" key={index}>
              <div className="h-3 w-24 rounded bg-slate-200" />
              <div className="mt-3 h-4 w-full rounded bg-slate-200" />
            </div>
          ))}
        </div>
      ) : visibleEntries.length > 0 ? (
        <ol className="min-h-0 flex-1 space-y-3 overflow-y-auto p-4">
          {visibleEntries.map((entry) => {
            const meta = getEventMeta(entry.eventType);
            const playerName = entry.playerId ? playerNames[entry.playerId] : null;
            const payloadItems = getPayloadItems(entry.payload);

            return (
              <li className="min-w-0 rounded-[16px] border border-violet-300/20 bg-[#12121a]/45 p-3 shadow-[inset_1px_1px_0_rgba(255,255,255,0.04)]" key={entry.id}>
                <div className="flex flex-wrap items-center gap-2">
                  <span
                    className={joinClassNames(
                      'rounded border px-2 py-1 text-xs font-bold leading-none',
                      toneClasses[meta.tone],
                    )}
                  >
                    {meta.label}
                  </span>
                  {entry.turnNumber ? (
                    <span className="text-xs font-semibold text-slate-500">
                      Хід {entry.turnNumber}
                    </span>
                  ) : null}
                  <span className="text-xs font-semibold text-slate-400">
                    {formatTime(entry.createdAt)}
                  </span>
                </div>

                {playerName ? (
                  <p className="mt-2 truncate text-xs font-semibold text-slate-500">
                    {playerName}
                  </p>
                ) : null}

                <p className="mt-1 break-words text-sm font-medium leading-5 text-slate-800">
                  {entry.message}
                </p>

                {payloadItems.length > 0 ? (
                  <div className="mt-3 flex flex-wrap gap-2">
                    {payloadItems.map((item) => (
                      <span
                        className="neo-chip max-w-full truncate rounded border px-2 py-1 text-xs font-semibold"
                        key={item.key}
                        title={`${payloadLabels[item.key]}: ${item.value}`}
                      >
                        {payloadLabels[item.key]}: {item.value}
                      </span>
                    ))}
                  </div>
                ) : null}
              </li>
            );
          })}
        </ol>
      ) : (
        <div className="flex min-h-40 items-center justify-center px-4 py-8 text-center text-sm font-semibold text-slate-500">
          Подій ще немає
        </div>
      )}
    </aside>
  );
}

export default GameLog;
