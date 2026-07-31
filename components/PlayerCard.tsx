import type { Company, GameState, Player, Tender } from '@/types';

type PlayerCardProps = {
  className?: string;
  gameState?: GameState | null;
  isCurrentTurn?: boolean;
  isCurrentUser?: boolean;
  player: Player;
};

type OwnedShare = {
  company: Company | null;
  companyId: string;
  count: number;
};

type OwnedTender = {
  tender: Tender | null;
  tenderId: string;
};

const currencyFormatter = new Intl.NumberFormat('uk-UA', {
  currency: 'USD',
  maximumFractionDigits: 0,
  style: 'currency',
});

function joinClassNames(...classes: Array<string | false | undefined>) {
  return classes.filter(Boolean).join(' ');
}

function formatMoney(value: number) {
  return currencyFormatter.format(value);
}

function formatInteger(value: number) {
  return new Intl.NumberFormat('uk-UA', {
    maximumFractionDigits: 0,
  }).format(value);
}

function getOwnedShares(player: Player, gameState?: GameState | null): OwnedShare[] {
  return Object.entries(player.shares)
    .filter(([, count]) => count > 0)
    .map(([companyId, count]) => ({
      company: gameState?.companies[companyId] ?? null,
      companyId,
      count,
    }))
    .sort((left, right) => right.count - left.count);
}

function getOwnedTenders(player: Player, gameState?: GameState | null): OwnedTender[] {
  return player.tenderIds.map((tenderId) => ({
    tender: gameState?.tenders[tenderId] ?? null,
    tenderId,
  }));
}

function StatItem({
  label,
  tone = 'default',
  value,
}: {
  label: string;
  tone?: 'default' | 'good' | 'warning';
  value: string;
}) {
  return (
    <div className="min-w-0">
      <p className="text-xs font-semibold uppercase tracking-normal text-slate-500">
        {label}
      </p>
      <p
        className={joinClassNames(
          'mt-1 truncate text-lg font-bold tracking-normal',
          tone === 'good' && 'text-emerald-700',
          tone === 'warning' && 'text-rose-700',
          tone === 'default' && 'text-slate-950',
        )}
      >
        {value}
      </p>
    </div>
  );
}

export function PlayerCard({
  className,
  gameState,
  isCurrentTurn,
  isCurrentUser,
  player,
}: PlayerCardProps) {
  const ownedShares = getOwnedShares(player, gameState);
  const ownedTenders = getOwnedTenders(player, gameState);
  const hasDebt = player.debtLocked || player.balance < 0;

  return (
    <article
      className={joinClassNames(
        'rounded-md border bg-white p-4 shadow-sm',
        isCurrentTurn ? 'border-emerald-500 ring-2 ring-emerald-100' : 'border-slate-200',
        hasDebt && 'border-rose-300',
        className,
      )}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-xs font-semibold uppercase tracking-normal text-slate-500">
            Місце {player.seatNumber}
          </p>
          <h3 className="mt-1 truncate text-xl font-bold tracking-normal text-slate-950">
            {player.name}
          </h3>
          <p className="mt-1 text-sm text-slate-600">
            {player.ring === 'inner' ? 'Внутрішнє коло' : 'Зовнішнє коло'} ·{' '}
            {player.cellId}
          </p>
        </div>

        <div className="flex shrink-0 flex-wrap justify-end gap-1">
          {isCurrentUser ? (
            <span className="rounded bg-slate-950 px-2 py-1 text-xs font-bold text-white">
              Ви
            </span>
          ) : null}
          {isCurrentTurn ? (
            <span className="rounded bg-emerald-100 px-2 py-1 text-xs font-bold text-emerald-800">
              Хід
            </span>
          ) : null}
          {player.isBot ? (
            <span className="rounded bg-slate-100 px-2 py-1 text-xs font-bold text-slate-700">
              Бот
            </span>
          ) : null}
        </div>
      </div>

      <div className="mt-4 grid grid-cols-2 gap-x-5 gap-y-4">
        <StatItem
          label="Баланс"
          tone={player.balance < 0 ? 'warning' : 'good'}
          value={formatMoney(player.balance)}
        />
        <StatItem label="Імідж" value={formatInteger(player.image)} />
        <StatItem label="Запас" value={formatInteger(player.inventory)} />
        <StatItem
          label="Зустрічі"
          value={`${player.successfulDeals}/${player.successfulDeals + player.failedDeals}`}
        />
      </div>

      <div className="mt-4 border-t border-slate-200 pt-4">
        <div className="flex items-center justify-between gap-3">
          <h4 className="text-sm font-bold text-slate-950">Акції</h4>
          <span className="text-xs font-semibold text-slate-500">
            {ownedShares.length}
          </span>
        </div>

        {ownedShares.length > 0 ? (
          <ul className="mt-3 space-y-2">
            {ownedShares.map(({ company, companyId, count }) => {
              const totalShares = company?.totalShares ?? 100;
              const ownershipPercent = Math.round((count / totalShares) * 100);

              return (
                <li className="flex items-center justify-between gap-3 text-sm" key={companyId}>
                  <span className="min-w-0 truncate font-medium text-slate-700">
                    {company?.name ?? companyId}
                  </span>
                  <span className="shrink-0 font-bold text-slate-950">
                    {count} шт. · {ownershipPercent}%
                  </span>
                </li>
              );
            })}
          </ul>
        ) : (
          <p className="mt-3 text-sm text-slate-500">Акцій ще немає</p>
        )}
      </div>

      <div className="mt-4 border-t border-slate-200 pt-4">
        <div className="flex items-center justify-between gap-3">
          <h4 className="text-sm font-bold text-slate-950">Тендери</h4>
          <span className="text-xs font-semibold text-slate-500">
            {ownedTenders.length}
          </span>
        </div>

        {ownedTenders.length > 0 ? (
          <ul className="mt-3 space-y-2">
            {ownedTenders.map(({ tender, tenderId }) => (
              <li className="flex items-center justify-between gap-3 text-sm" key={tenderId}>
                <span className="min-w-0 truncate font-medium text-slate-700">
                  {tender?.country ?? tenderId}
                </span>
                {tender ? (
                  <span className="shrink-0 font-bold text-slate-950">
                    {formatMoney(tender.price)}
                  </span>
                ) : null}
              </li>
            ))}
          </ul>
        ) : (
          <p className="mt-3 text-sm text-slate-500">Тендерів ще немає</p>
        )}
      </div>

      {player.skipTurns > 0 || hasDebt ? (
        <div className="mt-4 border-t border-slate-200 pt-4 text-sm font-semibold">
          {player.skipTurns > 0 ? (
            <p className="text-blue-700">Пропускає ходів: {player.skipTurns}</p>
          ) : null}
          {hasDebt ? <p className="text-rose-700">Борг блокує рух</p> : null}
        </div>
      ) : null}
    </article>
  );
}

export default PlayerCard;
