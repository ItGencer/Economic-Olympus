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
  cell_deal_pending: { label: 'Угода', tone: 'amber' },
  cell_director: { label: 'Директор', tone: 'violet' },
  cell_image_pending: { label: 'Імідж', tone: 'blue' },
  cell_random: { label: 'Випадок', tone: 'violet' },
  cell_reputation: { label: 'Репутація', tone: 'blue' },
  cell_salary: { label: 'Дохід', tone: 'emerald' },
  cell_start: { label: 'Старт', tone: 'emerald' },
  cell_tax: { label: 'Податок', tone: 'rose' },
  cell_tender_pending: { label: 'Тендер', tone: 'amber' },
  cell_vacation: { label: 'Відпустка', tone: 'blue' },
  ceo_election_failed: { label: 'CEO', tone: 'rose' },
  ceo_election_won: { label: 'CEO', tone: 'emerald' },
  client_declined: { label: 'Клієнт', tone: 'slate' },
  client_scores_rolled: { label: 'Клієнт', tone: 'blue' },
  client_stock_sold: { label: 'Клієнт', tone: 'emerald' },
  company_purchase_skipped: { label: 'Компанія', tone: 'slate' },
  company_shares_purchased: { label: 'Акції', tone: 'emerald' },
  company_sold_out: { label: 'Компанія', tone: 'violet' },
  deal_declined: { label: 'Угода', tone: 'slate' },
  deal_failed: { label: 'Угода', tone: 'rose' },
  deal_successful: { label: 'Угода', tone: 'emerald' },
  debt_locked: { label: 'Борг', tone: 'rose' },
  debt_unlocked: { label: 'Борг', tone: 'emerald' },
  director_no_change: { label: 'Директор', tone: 'slate' },
  directors_elected: { label: 'Директор', tone: 'emerald' },
  dice_rolled: { label: 'Кубик', tone: 'blue' },
  game_started: { label: 'Гра', tone: 'emerald' },
  game_ended_manually: { label: 'Гра', tone: 'rose' },
  image_declined: { label: 'Імідж', tone: 'slate' },
  image_purchased: { label: 'Імідж', tone: 'emerald' },
  outer_ring_choice_pending: { label: 'Зовнішнє коло', tone: 'amber' },
  outer_ring_moved: { label: 'Зовнішнє коло', tone: 'emerald' },
  outer_ring_stayed: { label: 'Зовнішнє коло', tone: 'slate' },
  tender_declined: { label: 'Тендер', tone: 'slate' },
  tender_fee_paid: { label: 'Тендер', tone: 'rose' },
  tender_owner_landed: { label: 'Тендер', tone: 'blue' },
  tender_purchased: { label: 'Тендер', tone: 'emerald' },
  turn_skipped: { label: 'Хід', tone: 'blue' },
};

const toneClasses: Record<EventTone, string> = {
  amber: 'border-amber-200 bg-amber-50 text-amber-800',
  blue: 'border-blue-200 bg-blue-50 text-blue-800',
  emerald: 'border-emerald-200 bg-emerald-50 text-emerald-800',
  rose: 'border-rose-200 bg-rose-50 text-rose-800',
  slate: 'border-slate-200 bg-slate-100 text-slate-700',
  violet: 'border-violet-200 bg-violet-50 text-violet-800',
};

const payloadLabels: Record<string, string> = {
  balanceAfter: 'Баланс',
  cell_id: 'Клітинка',
  cell_type: 'Тип',
  debt_locked: 'Борг',
  decision: 'Вибір',
  die: 'Кубик',
  income: 'Дохід',
  imageGain: 'Імідж',
  price: 'Ціна',
  share_count: 'Акції',
  successful: 'Успіх',
  supportPercent: 'Підтримка',
  to_cell_id: 'Куди',
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
    .slice(0, 3);
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
        'flex min-h-0 flex-col rounded-md border border-slate-200 bg-white shadow-sm',
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
            <div className="animate-pulse rounded-md bg-slate-100 p-3" key={index}>
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
              <li className="min-w-0 rounded-md border border-slate-200 p-3" key={entry.id}>
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
                        className="max-w-full truncate rounded border border-slate-200 bg-slate-50 px-2 py-1 text-xs font-semibold text-slate-600"
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
