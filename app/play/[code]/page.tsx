'use client';

import Link from 'next/link';
import Image from 'next/image';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import AnimatedNumber from '@/components/AnimatedNumber';
import Board from '@/components/Board';
import ConnectionStatus from '@/components/ConnectionStatus';
import D20Dice from '@/components/D20Dice';
import Dice from '@/components/Dice';
import GameLog from '@/components/GameLog';
import PlayerAvatarToken from '@/components/PlayerAvatarToken';
import SiteHeader from '@/components/SiteHeader';
import { useGameRealtime } from '@/hooks/useGameRealtime';
import {
  avatarColorOptions,
  avatarStyleOptions,
  normalizeAvatarColor,
  normalizeAvatarStyle,
  type PlayerAvatarStyle,
} from '@/lib/playerAvatarConfig';
import { getSupabaseClient, requireAuthenticatedUser } from '@/lib/supabase';
import type {
  Company,
  CompanyId,
  GameState,
  PendingAction,
  Player,
  PlayerId,
} from '@/types';

type PlayPageProps = {
  params: {
    code: string;
  };
};

type RpcArgs = Record<string, number | string | null>;
type CasinoParity = 'even' | 'odd';
type CasinoStep = 'intro' | 'bet';
type CompanyCatalogItem = {
  id: CompanyId;
  name: string;
  sharePrice: number;
  totalShares: number;
};

const COMPANY_SHARE_POOL = 2000;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

const companyCatalog: CompanyCatalogItem[] = [
  {
    id: 'company-logistics',
    name: 'Логістика',
    sharePrice: 1500,
    totalShares: COMPANY_SHARE_POOL,
  },
  {
    id: 'company-retail',
    name: 'Ритейл',
    sharePrice: 500,
    totalShares: COMPANY_SHARE_POOL,
  },
  {
    id: 'company-tech',
    name: 'Технології',
    sharePrice: 8000,
    totalShares: COMPANY_SHARE_POOL,
  },
  {
    id: 'company-finance',
    name: 'Фінанси',
    sharePrice: 5000,
    totalShares: COMPANY_SHARE_POOL,
  },
  {
    id: 'company-energy',
    name: 'Енергетика',
    sharePrice: 10000,
    totalShares: COMPANY_SHARE_POOL,
  },
  {
    id: 'company-media',
    name: 'Медіа',
    sharePrice: 2500,
    totalShares: COMPANY_SHARE_POOL,
  },
];

const d6PipPositions: Record<number, number[]> = {
  1: [5],
  2: [1, 9],
  3: [1, 5, 9],
  4: [1, 3, 7, 9],
  5: [1, 3, 5, 7, 9],
  6: [1, 3, 4, 6, 7, 9],
};

type ImageCardVariant = {
  alt: string;
  description: string;
  imageSrc: string;
  title: string;
};

type RandomCardVariant = {
  alt: string;
  imageSrc: string;
  key: string;
  negativeText: string;
  positiveText: string;
  title: string;
};

const imageCardVariants: ImageCardVariant[] = [
  {
    alt: 'Дошка розслідування',
    description:
      'Замовте прозоре розслідування та покажіть партнерам, що ваш бізнес грає чесно.',
    imageSrc: '/image-cards/Investigation.png',
    title: 'Розслідування',
  },
  {
    alt: 'Терези правосуддя',
    description:
      'Оплатіть юридичну підтримку, щоб захистити репутацію та зміцнити довіру клієнтів.',
    imageSrc: '/image-cards/Law.jpg',
    title: 'Юридична підтримка',
  },
  {
    alt: 'Новий стиль зачіски',
    description:
      'Оновіть стиль керівника та додайте бренду впізнаваності перед важливими зустрічами.',
    imageSrc: '/image-cards/New_Style.jpg',
    title: 'Новий стиль',
  },
  {
    alt: 'Преміальний телефон',
    description:
      'Придбайте преміальний телефон для публічних появ та підкресліть статус компанії.',
    imageSrc: '/image-cards/Phone.png',
    title: 'Преміальний телефон',
  },
  {
    alt: 'Переїзд компанії',
    description:
      'Організуйте переїзд у престижну локацію, щоб бізнес виглядав сильніше для партнерів.',
    imageSrc: '/image-cards/New_movement.jpg',
    title: 'Новий переїзд',
  },
  {
    alt: 'Портретна фотосесія',
    description:
      'Проведіть фотосесію для медіа та підготуйте професійний образ для ринку.',
    imageSrc: '/image-cards/Photo.jpg',
    title: 'Фотосесія',
  },
  {
    alt: 'Мікрофони преси',
    description:
      'Зберіть пресконференцію, щоб гучно оголосити про успіхи компанії.',
    imageSrc: '/image-cards/Press.jpg',
    title: 'Пресконференція',
  },
  {
    alt: 'Будівля школи',
    description:
      'Підтримайте будівництво школи та отримайте сильний соціальний імідж.',
    imageSrc: '/image-cards/Building_School.jpg',
    title: 'Будівництво школи',
  },
  {
    alt: 'Онлайн реклама',
    description:
      'Запустіть рекламну кампанію, щоб про ваш бренд говорили частіше.',
    imageSrc: '/image-cards/ADS.png',
    title: 'Рекламна кампанія',
  },
  {
    alt: 'Консультант за ноутбуком',
    description:
      'Оплатіть консультацію експерта та перетворіть поради на впевненість ринку.',
    imageSrc: '/image-cards/Consultation.jpg',
    title: 'Консультація експерта',
  },
  {
    alt: 'Діловий костюм',
    description:
      'Купіть діловий костюм для перемовин, де перше враження вирішує багато.',
    imageSrc: '/image-cards/Suit.png',
    title: 'Діловий костюм',
  },
  {
    alt: 'Компʼютерна допомога',
    description:
      'Інвестуйте в IT-допомогу, щоб цифровий образ компанії виглядав надійно.',
    imageSrc: '/image-cards/Help_OS.jpg',
    title: 'Допомога IT',
  },
  {
    alt: 'Символ благодійності',
    description:
      'Зробіть благодійний внесок і покажіть, що компанія працює не лише заради прибутку.',
    imageSrc: '/image-cards/Helper.png',
    title: 'Благодійність',
  },
];

const randomCardVariants: RandomCardVariant[] = [
  {
    alt: 'Дошка розслідування',
    imageSrc: '/image-cards/Investigation.png',
    key: 'Investigation',
    negativeText: 'Перевірка знайшла стару помилку в документах.',
    positiveText: 'Розслідування прибрало ризик і врятувало угоду.',
    title: 'Розслідування',
  },
  {
    alt: 'Терези правосуддя',
    imageSrc: '/image-cards/Law.jpg',
    key: 'Law',
    negativeText: 'Юридична суперечка потребує термінових витрат.',
    positiveText: 'Юристи виграли спір і повернули компанії гроші.',
    title: 'Юридична підтримка',
  },
  {
    alt: 'Новий стиль зачіски',
    imageSrc: '/image-cards/New_Style.jpg',
    key: 'New_Style',
    negativeText: 'Невдалий стиль зіпсував публічну зустріч.',
    positiveText: 'Оновлений образ дав несподіваний рекламний ефект.',
    title: 'Новий стиль',
  },
  {
    alt: 'Преміальний телефон',
    imageSrc: '/image-cards/Phone.png',
    key: 'Phone',
    negativeText: 'Преміальний гаджет розбили перед презентацією.',
    positiveText: 'Корисний дзвінок приніс швидкий контракт.',
    title: 'Телефон',
  },
  {
    alt: 'Переїзд компанії',
    imageSrc: '/image-cards/New_movement.jpg',
    key: 'New_movement',
    negativeText: 'Переїзд затягнувся і зірвав робочий тиждень.',
    positiveText: 'Нова локація привела більше клієнтів.',
    title: 'Переїзд',
  },
  {
    alt: 'Портретна фотосесія',
    imageSrc: '/image-cards/Photo.jpg',
    key: 'Photo',
    negativeText: 'Невдале фото стало приводом для критики.',
    positiveText: 'Фото потрапило в медіа і принесло увагу.',
    title: 'Фотосесія',
  },
  {
    alt: 'Мікрофони преси',
    imageSrc: '/image-cards/Press.jpg',
    key: 'Press',
    negativeText: 'Преса перекрутила слова і створила проблему.',
    positiveText: 'Добра згадка в пресі привела нові гроші.',
    title: 'Преса',
  },
  {
    alt: 'Будівля школи',
    imageSrc: '/image-cards/Building_School.jpg',
    key: 'Building_School',
    negativeText: 'Будівельний підрядник виставив додатковий рахунок.',
    positiveText: 'Соціальний проєкт отримав премію від партнерів.',
    title: 'Будівництво школи',
  },
  {
    alt: 'Онлайн реклама',
    imageSrc: '/image-cards/ADS.png',
    key: 'ADS',
    negativeText: 'Рекламна кампанія злила бюджет без результату.',
    positiveText: 'Реклама несподівано привела хвилю продажів.',
    title: 'Реклама',
  },
  {
    alt: 'Консультант за ноутбуком',
    imageSrc: '/image-cards/Consultation.jpg',
    key: 'Consultation',
    negativeText: 'Консультація виявилась дорожчою, ніж планували.',
    positiveText: 'Порада експерта швидко окупилась.',
    title: 'Консультація',
  },
  {
    alt: 'Діловий костюм',
    imageSrc: '/image-cards/Suit.png',
    key: 'Suit',
    negativeText: 'Непередбачена покупка костюма вдарила по бюджету.',
    positiveText: 'Солідний вигляд допоміг домовитись вигідніше.',
    title: 'Діловий костюм',
  },
  {
    alt: 'Компʼютерна допомога',
    imageSrc: '/image-cards/Help_OS.jpg',
    key: 'Help_OS',
    negativeText: 'Технічний збій зупинив роботу сервісу.',
    positiveText: 'IT-допомога врятувала важливий запуск.',
    title: 'IT-допомога',
  },
  {
    alt: 'Символ благодійності',
    imageSrc: '/image-cards/Helper.png',
    key: 'Helper',
    negativeText: 'Благодійний збір потребував додаткових витрат.',
    positiveText: 'Добра справа принесла несподівану підтримку.',
    title: 'Благодійність',
  },
];

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
  deal_decision: 'Ділова зустріч',
  image_offer: 'Імідж',
  negative_reputation: 'Негативна репутація',
  outer_ring_choice: 'Перехід кола',
  random_event: 'Random',
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

const percentFormatter = new Intl.NumberFormat('uk-UA', {
  maximumFractionDigits: 2,
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

function formatPercent(value: number) {
  return `${percentFormatter.format(value)}%`;
}

function formatRing(ring: Player['ring']) {
  return ring === 'inner' ? 'Внутрішнє коло' : 'Зовнішнє коло';
}

function getSharePercent(shareCount: number, totalShares: number) {
  if (totalShares <= 0) {
    return 0;
  }

  return (shareCount / totalShares) * 100;
}

function getSoldCompanyShares(company?: Company) {
  if (!company) {
    return 0;
  }

  return Object.values(company.shareholders).reduce(
    (total, shareCount) => total + shareCount,
    0,
  );
}

function formatCasinoParity(value: CasinoParity) {
  return value === 'even' ? 'Парне' : 'Непарне';
}

function formatRandomSign(value: string) {
  return value === 'negative' ? 'Негативний випадок' : 'Позитивний випадок';
}

function D6Face({ rolling, value }: { rolling?: boolean; value: number | null }) {
  const activePips = value ? d6PipPositions[value] ?? [] : [];

  return (
    <div
      aria-label={value ? `Кубик: ${value}` : 'Кубик не кинуто'}
      className={joinClassNames(
        'neo-panel-pressed mx-auto grid h-24 w-24 shrink-0 grid-cols-3 grid-rows-3 gap-1 rounded-[18px] border border-rose-300/40 bg-white p-4 shadow-2xl shadow-rose-950/30 ring-4 ring-white/10',
        rolling && 'neo-dice-rolling',
      )}
      role="img"
    >
      {Array.from({ length: 9 }, (_, index) => {
        const position = index + 1;

        return (
          <span
            className={joinClassNames(
              'h-4 w-4 self-center justify-self-center rounded-full',
              activePips.includes(position) ? 'bg-slate-950' : 'bg-transparent',
            )}
            key={position}
          />
        );
      })}
    </div>
  );
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

function readPlayerProfileSaveErrorMessage(error: unknown) {
  const message = readErrorMessage(error);

  if (
    (message.includes('update_player_avatar') ||
      message.includes('update_player_profile')) &&
    message.includes('schema cache')
  ) {
    return 'Функція профілю гравця ще не застосована в Supabase. Виконай SQL з файлу supabase/sql/apply_player_profile_customization.sql у Supabase SQL Editor, потім онови сторінку.';
  }

  return message;
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

function readPayloadNumber(
  payload: Record<string, unknown>,
  key: string,
  fallback = 0,
) {
  const value = payload[key];

  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === 'string') {
    const parsedValue = Number(value);

    if (Number.isFinite(parsedValue)) {
      return parsedValue;
    }
  }

  return fallback;
}

function readPayloadString(
  payload: Record<string, unknown>,
  key: string,
  fallback = '',
) {
  const value = payload[key];

  return typeof value === 'string' ? value : fallback;
}

function readPayloadBoolean(
  payload: Record<string, unknown>,
  key: string,
  fallback = false,
) {
  const value = payload[key];

  return typeof value === 'boolean' ? value : fallback;
}

function readPayloadNumberArray(payload: Record<string, unknown>, key: string) {
  const value = payload[key];

  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter(
    (item): item is number => typeof item === 'number' && Number.isFinite(item),
  );
}

function parseRpcJson(value: unknown): unknown {
  if (typeof value !== 'string') {
    return value;
  }

  try {
    return JSON.parse(value) as unknown;
  } catch {
    return value;
  }
}

function readRpcStateSnapshot(value: unknown): unknown {
  const parsedValue = parseRpcJson(value);

  if (Array.isArray(parsedValue)) {
    return readRpcStateSnapshot(parsedValue[0]);
  }

  if (isRecord(parsedValue)) {
    if ('state' in parsedValue) {
      return parseRpcJson(parsedValue.state);
    }

    if (Array.isArray(parsedValue.players)) {
      return parsedValue;
    }
  }

  return undefined;
}

function readPlayerFromStateSnapshot(
  snapshot: unknown,
  playerId: PlayerId | null | undefined,
) {
  if (!playerId) {
    return null;
  }

  const stateSnapshot = readRpcStateSnapshot(snapshot) ?? snapshot;

  if (!isRecord(stateSnapshot) || !Array.isArray(stateSnapshot.players)) {
    return null;
  }

  return (
    (stateSnapshot.players as Player[]).find((player) => player.id === playerId) ??
    null
  );
}

function readPlayerTimestamp(player: Player | null | undefined) {
  if (!player) {
    return 0;
  }

  const timestamp = Date.parse(player.updatedAt);

  return Number.isNaN(timestamp) ? 0 : timestamp;
}

function haveSamePlayerStats(left: Player, right: Player) {
  return (
    left.balance === right.balance &&
    left.image === right.image &&
    left.inventory === right.inventory &&
    left.successfulDeals === right.successfulDeals &&
    left.failedDeals === right.failedDeals &&
    left.debtLocked === right.debtLocked &&
    Boolean(left.debtWarning) === Boolean(right.debtWarning) &&
    Boolean(left.eliminated) === Boolean(right.eliminated) &&
    left.skipTurns === right.skipTurns &&
    left.cellId === right.cellId &&
    left.ring === right.ring &&
    JSON.stringify(left.shares) === JSON.stringify(right.shares) &&
    JSON.stringify(left.tenderIds) === JSON.stringify(right.tenderIds) &&
    JSON.stringify(left.directorIds) === JSON.stringify(right.directorIds)
  );
}

function buildOptimisticPlayerSnapshot(
  rpcName: string,
  args: RpcArgs,
  action: PendingAction | null,
  player: Player | null,
) {
  if (!action || !player) {
    return null;
  }

  if (
    rpcName === 'resolve_image_offer' &&
    action.type === 'image_offer' &&
    args.p_decision === 'accept'
  ) {
    const price = readPayloadNumber(action.payload, 'price');
    const imageGain = readPayloadNumber(action.payload, 'imageGain');
    const balance = player.balance - price;

    return {
      ...player,
      balance,
      debtLocked: balance < 0,
      image: player.image + imageGain,
      updatedAt: new Date().toISOString(),
    };
  }

  return null;
}

function hashString(value: string) {
  let hash = 2166136261;

  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }

  return hash >>> 0;
}

function pickImageCardVariant(seed: string) {
  return imageCardVariants[hashString(seed) % imageCardVariants.length];
}

function pickRandomCardVariant(key: string, seed: string) {
  return (
    randomCardVariants.find((variant) => variant.key === key) ??
    randomCardVariants[hashString(seed) % randomCardVariants.length]
  );
}

function buildActionDetails(action: PendingAction) {
  const detailKeys = [
    ['cellId', action.cellId ?? null],
    ['coefficient', readPayloadValue(action.payload, 'coefficient')],
    ['income', readPayloadValue(action.payload, 'income')],
    ['importance', readPayloadValue(action.payload, 'importance')],
    ['score', readPayloadValue(action.payload, 'score')],
    ['amount', readPayloadValue(action.payload, 'amount')],
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
  browserPlayerId,
  currentTurnPlayerId,
  players,
}: {
  browserPlayerId: PlayerId | null;
  currentTurnPlayerId: PlayerId | null;
  players: Player[];
}) {
  return (
    <div className="flex gap-2 overflow-x-auto pb-1">
      {players.map((player) => {
        const isTurn = player.id === currentTurnPlayerId;
        const isBrowserPlayer = player.id === browserPlayerId;
        const isEliminated = Boolean(player.eliminated);

        return (
          <div
            aria-current={isTurn ? 'true' : undefined}
            className={joinClassNames(
              'min-w-36 rounded-[16px] border px-3 py-2 text-left transition',
              isEliminated ? 'opacity-60' : undefined,
              isTurn
                ? 'border-violet-300 bg-violet-500/20 text-violet-50 ring-2 ring-violet-400/35'
                : isBrowserPlayer
                  ? 'border-violet-300/45 bg-[#181824]/80 text-slate-100 ring-1 ring-violet-300/20'
                  : 'border-violet-300/20 bg-[#181824]/70 text-slate-300',
            )}
            key={player.id}
          >
            <span className="flex items-center gap-2">
              <PlayerAvatarToken
                avatarColor={player.avatarColor}
                avatarStyle={player.avatarStyle}
                name={player.name}
                size="sm"
              />
              <span className="min-w-0">
                <span className="block truncate text-sm font-bold">
                  {player.name}
                </span>
                <span className="mt-1 flex flex-wrap gap-1">
                  <span className="neo-chip rounded px-1.5 py-0.5 text-[11px] font-bold">
                    Місце {player.seatNumber}
                  </span>
                  {isTurn ? (
                    <span className="rounded bg-violet-500/20 px-1.5 py-0.5 text-[11px] font-bold text-fuchsia-100 ring-1 ring-violet-300/35">
                      Хід
                    </span>
                  ) : null}
                  {isBrowserPlayer ? (
                    <span className="rounded bg-slate-950 px-1.5 py-0.5 text-[11px] font-bold text-white">
                      Ви
                    </span>
                  ) : null}
                  {isEliminated ? (
                    <span className="rounded bg-rose-500/20 px-1.5 py-0.5 text-[11px] font-bold text-rose-100 ring-1 ring-rose-300/35">
                      Вибув
                    </span>
                  ) : null}
                </span>
              </span>
            </span>
          </div>
        );
      })}
    </div>
  );
}

function PrivatePlayerStatsModal({
  gameState,
  onClose,
  onPlayerUpdated,
  open,
  player,
}: {
  gameState: GameState;
  onClose: () => void;
  onPlayerUpdated?: (stateSnapshot?: unknown) => Promise<void> | void;
  open: boolean;
  player: Player;
}) {
  const [displayName, setDisplayName] = useState(player.name);
  const [avatarStyle, setAvatarStyle] = useState<PlayerAvatarStyle>(
    normalizeAvatarStyle(player.avatarStyle),
  );
  const [avatarColor, setAvatarColor] = useState(
    normalizeAvatarColor(player.avatarColor),
  );
  const [profileSaveError, setProfileSaveError] = useState<string | null>(null);
  const [profileSaveStatus, setProfileSaveStatus] = useState<string | null>(null);
  const [profileSaving, setProfileSaving] = useState(false);

  useEffect(() => {
    if (!open) {
      return;
    }

    setDisplayName(player.name);
    setAvatarStyle(normalizeAvatarStyle(player.avatarStyle));
    setAvatarColor(normalizeAvatarColor(player.avatarColor));
    setProfileSaveError(null);
    setProfileSaveStatus(null);
  }, [open, player.avatarColor, player.avatarStyle, player.id, player.name]);

  if (!open) {
    return null;
  }

  const companyRows = companyCatalog.map((companyItem) => {
    const company = gameState.companies[companyItem.id];
    const totalShares = company?.totalShares ?? companyItem.totalShares;
    const soldShares = getSoldCompanyShares(company);
    const ownedShares = player.shares[companyItem.id] ?? 0;
    const availableShares = Math.max(totalShares - soldShares, 0);

    return {
      availablePercent: getSharePercent(availableShares, totalShares),
      availableShares,
      id: companyItem.id,
      name: company?.name ?? companyItem.name,
      ownedPercent: getSharePercent(ownedShares, totalShares),
      ownedShares,
      sharePrice: company?.sharePrice ?? companyItem.sharePrice,
      totalShares,
    };
  });
  const tenders = player.tenderIds
    .map((tenderId) => gameState.tenders[tenderId])
    .filter(Boolean);
  const meetingsTotal = player.successfulDeals + player.failedDeals;
  const normalizedDisplayName = displayName.trim().replace(/\s+/g, ' ');
  const nameChanged = normalizedDisplayName !== player.name;
  const avatarChanged =
    avatarStyle !== normalizeAvatarStyle(player.avatarStyle) ||
    avatarColor !== normalizeAvatarColor(player.avatarColor);
  const profileChanged = nameChanged || avatarChanged;
  const canSaveProfile =
    profileChanged &&
    normalizedDisplayName.length >= 2 &&
    normalizedDisplayName.length <= 32;

  async function handleSavePlayerProfile() {
    setProfileSaveError(null);
    setProfileSaveStatus(null);
    setProfileSaving(true);

    try {
      const supabase = getSupabaseClient();
      const { data, error: saveError } = await supabase.rpc('update_player_profile', {
        p_game_id: gameState.gameId,
        p_display_name: normalizedDisplayName,
        p_avatar_style: avatarStyle,
        p_avatar_color: avatarColor,
      });

      if (saveError) {
        throw saveError;
      }

      await onPlayerUpdated?.(readRpcStateSnapshot(data));
      setProfileSaveStatus('Профіль гравця збережено');
    } catch (caughtError) {
      setProfileSaveError(readPlayerProfileSaveErrorMessage(caughtError));
    } finally {
      setProfileSaving(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-[#070710]/65 px-4 py-6 backdrop-blur-md"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) {
          onClose();
        }
      }}
      role="presentation"
    >
      <section
        aria-labelledby="private-player-card-title"
        aria-modal="true"
        className="neo-panel neo-modal-panel max-h-[92vh] w-full max-w-3xl overflow-y-auto rounded-[20px] border border-violet-300/30 bg-white shadow-2xl shadow-slate-950/25"
        role="dialog"
      >
        <header className="flex items-start justify-between gap-4 border-b border-violet-300/20 px-5 py-4">
          <div className="min-w-0">
            <p className="text-xs font-bold uppercase tracking-normal text-emerald-700">
              Приватна статистика
            </p>
            <h2
              className="mt-1 truncate text-2xl font-bold tracking-normal text-slate-950"
              id="private-player-card-title"
            >
              {normalizedDisplayName || player.name}
            </h2>
          </div>
          <button
            aria-label="Закрити картку гравця"
            className="neo-button inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-[16px] border border-violet-300/30 text-lg font-bold text-slate-300 transition hover:bg-violet-500/10"
            onClick={onClose}
            type="button"
          >
            ×
          </button>
        </header>

        <div className="space-y-5 px-5 py-5">
          <section className="neo-panel rounded-[18px] border border-violet-300/25 bg-slate-50 p-4">
            <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
              <div className="flex items-center gap-4">
                <PlayerAvatarToken
                  avatarColor={avatarColor}
                  avatarStyle={avatarStyle}
                  className="shadow-[0_0_28px_rgba(192,132,252,0.55),inset_0_0_14px_rgba(168,85,247,0.22)]"
                  key={`${avatarStyle}-${avatarColor}-preview`}
                  name={normalizedDisplayName || player.name}
                  size="lg"
                />
                <div className="min-w-0">
                  <p className="text-xs font-bold uppercase tracking-normal text-fuchsia-200">
                    Фішка
                  </p>
                  <h3 className="mt-1 text-lg font-bold tracking-normal text-slate-950">
                    {normalizedDisplayName || player.name}
                  </h3>
                  <p className="mt-1 text-sm font-semibold text-slate-500">
                    Обери ім'я, стиль і неоновий колір своєї фішки.
                  </p>
                </div>
              </div>

              <button
                className="neo-button h-11 rounded-[16px] bg-slate-950 px-5 text-sm font-bold text-white transition hover:bg-slate-800 disabled:cursor-not-allowed disabled:opacity-50"
                disabled={profileSaving || !canSaveProfile}
                onClick={() => void handleSavePlayerProfile()}
                type="button"
              >
                {profileSaving ? 'Зберігаємо...' : 'Зберегти'}
              </button>
            </div>

            <div className="mt-4 grid gap-4 lg:grid-cols-[minmax(0,240px)_minmax(0,1fr)]">
              <label className="block min-w-0 lg:col-span-2">
                <span className="text-xs font-bold uppercase tracking-normal text-slate-500">
                  Ім'я гравця
                </span>
                <input
                  className="mt-2 h-11 w-full rounded-[16px] border border-violet-300/30 bg-[#12121a] px-3 text-sm font-bold text-violet-50 outline-none transition [color-scheme:dark] placeholder:text-slate-500 focus:border-fuchsia-300/70 focus:ring-4 focus:ring-violet-500/20"
                  maxLength={32}
                  minLength={2}
                  onChange={(event) => setDisplayName(event.target.value)}
                  placeholder="Ім'я над фішкою"
                  type="text"
                  value={displayName}
                />
                <span className="mt-1 block text-xs font-semibold text-slate-500">
                  Від 2 до 32 символів. Це ім'я буде показане над фішкою на дошці.
                </span>
              </label>

              <label className="block min-w-0">
                <span className="text-xs font-bold uppercase tracking-normal text-slate-500">
                  Стиль фішки
                </span>
                <select
                  className="mt-2 h-11 w-full rounded-[16px] border border-violet-300/30 bg-[#12121a] px-3 text-sm font-bold text-violet-50 [color-scheme:dark]"
                  onChange={(event) =>
                    setAvatarStyle(normalizeAvatarStyle(event.target.value))
                  }
                  value={avatarStyle}
                >
                  {avatarStyleOptions.map((option) => (
                    <option
                      className="bg-[#12121a] text-violet-50"
                      key={option.id}
                      value={option.id}
                    >
                      {option.label}
                    </option>
                  ))}
                </select>
              </label>

              <div>
                <p className="text-xs font-bold uppercase tracking-normal text-slate-500">
                  Колір фішки
                </p>
                <div
                  aria-label="Колір фішки"
                  className="mt-2 flex flex-wrap gap-2"
                  role="radiogroup"
                >
                  {avatarColorOptions.map((color) => {
                    const selected = color === avatarColor;

                    return (
                      <button
                        aria-checked={selected}
                        aria-label={`Колір ${color}`}
                        className={joinClassNames(
                          'h-10 w-10 rounded-full border transition hover:scale-105',
                          selected
                            ? 'border-fuchsia-100 ring-2 ring-fuchsia-300 ring-offset-2 ring-offset-[#12121a]'
                            : 'border-violet-200/50',
                        )}
                        key={color}
                        onClick={() => setAvatarColor(color)}
                        role="radio"
                        style={{ backgroundColor: color }}
                        type="button"
                      />
                    );
                  })}
                </div>
              </div>
            </div>

            <div className="mt-4">
              <p className="text-xs font-bold uppercase tracking-normal text-slate-500">
                Живий вибір стилю
              </p>
              <div className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
                {avatarStyleOptions.map((option) => {
                  const selected = option.id === avatarStyle;

                  return (
                    <button
                      aria-pressed={selected}
                      className={joinClassNames(
                        'flex min-h-24 flex-col items-center justify-center gap-2 rounded-[16px] border px-2 py-3 text-center text-xs font-bold transition',
                        selected
                          ? 'border-fuchsia-200 bg-violet-500/22 text-fuchsia-50 ring-2 ring-fuchsia-300/45'
                          : 'border-violet-300/25 bg-[#12121a]/45 text-slate-300 hover:border-fuchsia-300/60 hover:bg-violet-500/12',
                      )}
                      key={option.id}
                      onClick={() => setAvatarStyle(option.id)}
                      type="button"
                    >
                      <PlayerAvatarToken
                        avatarColor={avatarColor}
                        avatarStyle={option.id}
                        key={`${option.id}-${avatarColor}-style-option`}
                        name={normalizedDisplayName || player.name}
                        size="sm"
                      />
                      <span>{option.label}</span>
                    </button>
                  );
                })}
              </div>
            </div>

            {profileSaveStatus ? (
              <p className="mt-3 rounded-[14px] bg-emerald-500/12 px-3 py-2 text-sm font-bold text-emerald-100">
                {profileSaveStatus}
              </p>
            ) : null}
            {profileSaveError ? (
              <p className="mt-3 rounded-[14px] bg-rose-500/12 px-3 py-2 text-sm font-bold text-rose-100">
                {profileSaveError}
              </p>
            ) : null}
          </section>

          <div className="grid gap-3 sm:grid-cols-3">
            <div className="neo-panel rounded-[18px] border border-slate-200 bg-slate-50 px-3 py-3">
              <p className="text-xs font-bold uppercase tracking-normal text-slate-500">
                Баланс
              </p>
              <AnimatedNumber
                className="mt-1 block text-lg font-bold text-slate-950"
                formatter={formatMoney}
                value={player.balance}
              />
            </div>
            <div className="neo-panel rounded-[18px] border border-slate-200 bg-slate-50 px-3 py-3">
              <p className="text-xs font-bold uppercase tracking-normal text-slate-500">
                Імідж
              </p>
              <AnimatedNumber
                className="mt-1 block text-lg font-bold text-slate-950"
                formatter={formatInteger}
                value={player.image}
              />
            </div>
            <div className="neo-panel rounded-[18px] border border-slate-200 bg-slate-50 px-3 py-3">
              <p className="text-xs font-bold uppercase tracking-normal text-slate-500">
                Зустрічі
              </p>
              <AnimatedNumber
                className="mt-1 block text-lg font-bold text-slate-950"
                formatter={formatInteger}
                value={meetingsTotal}
              />
              <p className="mt-1 text-xs font-semibold text-slate-500">
                {formatInteger(player.successfulDeals)} успішних /{' '}
                {formatInteger(player.failedDeals)} провалених
              </p>
            </div>
          </div>

          <section>
            <h3 className="text-base font-bold tracking-normal text-slate-950">
              Акції компаній
            </h3>
            <div className="mt-3 grid gap-2">
              {companyRows.map((company) => (
                <div
                  className="neo-panel grid gap-3 rounded-[18px] border border-slate-200 bg-white px-3 py-3 sm:grid-cols-[minmax(0,1fr)_160px_160px]"
                  key={company.id}
                >
                  <div className="min-w-0">
                    <p className="truncate text-sm font-bold text-slate-950">
                      {company.name}
                    </p>
                    <p className="mt-1 text-xs font-semibold text-slate-500">
                      1 акція: {formatMoney(company.sharePrice)}
                    </p>
                  </div>
                  <div>
                    <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                      Куплено
                    </p>
                    <p className="mt-1 text-sm font-bold text-slate-950">
                      {formatInteger(company.ownedShares)} /{' '}
                      {formatPercent(company.ownedPercent)}
                    </p>
                  </div>
                  <div>
                    <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                      Вільно
                    </p>
                    <p className="mt-1 text-sm font-bold text-emerald-700">
                      {formatInteger(company.availableShares)} /{' '}
                      {formatPercent(company.availablePercent)}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          </section>

          <section className="grid gap-3 sm:grid-cols-2">
            <div className="neo-panel rounded-[18px] border border-slate-200 bg-slate-50 px-3 py-3">
              <h3 className="text-base font-bold tracking-normal text-slate-950">
                Тендери
              </h3>
              {tenders.length > 0 ? (
                <ul className="mt-2 space-y-1 text-sm font-semibold text-slate-700">
                  {tenders.map((tender) => (
                    <li key={tender.id}>
                      {tender.country}: {formatMoney(tender.buyout)}
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="mt-2 text-sm font-semibold text-slate-500">
                  Тендерів поки немає.
                </p>
              )}
            </div>
            <div className="neo-panel rounded-[18px] border border-slate-200 bg-slate-50 px-3 py-3">
              <h3 className="text-base font-bold tracking-normal text-slate-950">
                Позиція
              </h3>
              <div className="mt-2 grid grid-cols-2 gap-2 text-sm font-semibold text-slate-700">
                <span>Коло</span>
                <span className="text-right text-slate-950">
                  {formatRing(player.ring)}
                </span>
                <span>Клітинка</span>
                <span className="text-right text-slate-950">
                  {player.cellId}
                </span>
              </div>
            </div>
          </section>
        </div>
      </section>
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
  onResolved: (
    stateSnapshot?: unknown,
    playerSnapshot?: Player | null,
  ) => Promise<void>;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [casinoBetInput, setCasinoBetInput] = useState('100');
  const [casinoParity, setCasinoParity] = useState<CasinoParity>('even');
  const [casinoStep, setCasinoStep] = useState<CasinoStep>('intro');
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
        const { data, error: rpcError } = await supabase.rpc(rpcName, args);

        if (rpcError) {
          throw rpcError;
        }

        await onResolved(
          readRpcStateSnapshot(data),
          buildOptimisticPlayerSnapshot(rpcName, args, action, activePlayer),
        );
      } catch (caughtError) {
        setError(readErrorMessage(caughtError));
      } finally {
        setBusy(false);
      }
    },
    [action, activePlayer, onResolved],
  );

  useEffect(() => {
    setCasinoStep('intro');
    setCasinoParity('even');
    setError(null);

    if (action?.type === 'casino_bet') {
      const nextStake = Math.max(
        0,
        Math.min(100, Math.floor(activePlayer?.balance ?? 0)),
      );

      setCasinoBetInput(String(nextStake));
    }

    if (action?.type === 'company_share_purchase') {
      const maxPurchasableShares = Math.max(
        0,
        Math.floor(readPayloadNumber(action.payload, 'maxPurchasableShares')),
      );

      setShareCount(maxPurchasableShares > 0 ? 1 : 0);
    } else {
      setShareCount(1);
    }
  }, [action?.id, action?.type, activePlayer?.balance]);

  if (!action) {
    return (
      <section className="neo-panel rounded-[18px] border border-slate-200 bg-white p-4 shadow-sm">
        <div className="flex items-center justify-between gap-3">
          <h2 className="text-base font-bold tracking-normal text-slate-950">
            Дія
          </h2>
          <span className="neo-chip rounded px-2 py-1 text-xs font-bold">
            Немає
          </span>
        </div>
      </section>
    );
  }

  const details = action.type === 'image_offer' ? [] : buildActionDetails(action);
  const imagePrice = readPayloadNumber(action.payload, 'price');
  const imageGain = readPayloadNumber(action.payload, 'imageGain');
  const imageCard =
    action.type === 'image_offer'
      ? pickImageCardVariant(action.id || action.cellId || action.createdAt)
      : null;
  const randomCard =
    action.type === 'random_event'
      ? pickRandomCardVariant(
          readPayloadString(action.payload, 'variantKey'),
          action.id || action.cellId || action.createdAt,
        )
      : null;
  const canAffordImage = Boolean(
    activePlayer && activePlayer.balance >= imagePrice,
  );
  const casinoBalance = Math.floor(activePlayer?.balance ?? 0);
  const casinoBetAmount = Number(casinoBetInput);
  const isCasinoBetValid =
    Number.isInteger(casinoBetAmount) &&
    casinoBetAmount >= 0;
  const canSubmitCasinoBet = Boolean(canAct && !busy && isCasinoBetValid);
  const casinoPhase = readPayloadString(action.payload, 'phase', 'initial');
  const casinoDice = readPayloadNumberArray(action.payload, 'dice');
  const casinoTotal = readPayloadNumber(action.payload, 'total');
  const casinoStoredBet = readPayloadNumber(
    action.payload,
    'betAmount',
    casinoBetAmount,
  );
  const casinoStoredParity = readPayloadString(
    action.payload,
    'parity',
    casinoParity,
  ) as CasinoParity;
  const casinoWon = readPayloadBoolean(action.payload, 'won');
  const casinoMultiplier = readPayloadNumber(action.payload, 'multiplier');
  const casinoPayout = readPayloadNumber(action.payload, 'payout');
  const casinoHasDice = casinoDice.length === 2;
  const casinoHasMultiplier = casinoMultiplier > 0;
  const casinoCanLaunchMultiplier =
    casinoPhase === 'dice_rolled' && casinoWon && !casinoHasMultiplier;
  const casinoCanCollect =
    (casinoPhase === 'dice_rolled' && !casinoWon) ||
    casinoPhase === 'multiplier_ready';
  const dealPhase = readPayloadString(action.payload, 'phase', 'initial');
  const dealCoefficient = readPayloadNumber(
    action.payload,
    'coefficient',
    readPayloadNumber(action.payload, 'importance', 0),
  );
  const dealUnitValue = readPayloadNumber(action.payload, 'unitValue', 1000);
  const dealDie = readPayloadNumber(action.payload, 'die');
  const dealScore = readPayloadNumber(
    action.payload,
    'score',
    dealCoefficient + dealDie,
  );
  const dealImage = readPayloadNumber(
    action.payload,
    'image',
    activePlayer?.image ?? 0,
  );
  const dealAmount = readPayloadNumber(action.payload, 'amount');
  const dealSuccessful = readPayloadBoolean(action.payload, 'successful');
  const dealDifference = readPayloadNumber(
    action.payload,
    'difference',
    dealImage - dealScore,
  );
  const reputationPhase = readPayloadString(action.payload, 'phase', 'initial');
  const reputationDie = readPayloadNumber(action.payload, 'die');
  const reputationImageLoss = reputationDie;
  const reputationImageBefore = readPayloadNumber(
    action.payload,
    'imageBefore',
    activePlayer?.image ?? 0,
  );
  const reputationImageAfter = readPayloadNumber(
    action.payload,
    'imageAfter',
    reputationImageBefore - reputationImageLoss,
  );
  const reputationCanStart = reputationPhase === 'initial';
  const reputationReadyToConfirm =
    reputationPhase === 'roll_ready' ||
    reputationPhase === 'dice_rolled' ||
    reputationPhase === 'multiplier_ready';
  const companyName = readPayloadString(action.payload, 'name', 'Компанія');
  const companyTotalShares = Math.max(
    1,
    Math.floor(
      readPayloadNumber(action.payload, 'totalShares', COMPANY_SHARE_POOL),
    ),
  );
  const companySoldShares = Math.max(
    0,
    Math.floor(readPayloadNumber(action.payload, 'soldShares')),
  );
  const companyAvailableShares = Math.max(
    0,
    Math.floor(
      readPayloadNumber(
        action.payload,
        'availableShares',
        companyTotalShares - companySoldShares,
      ),
    ),
  );
  const companyPlayerShares = Math.max(
    0,
    Math.floor(readPayloadNumber(action.payload, 'playerShares')),
  );
  const companySharePrice = Math.max(
    0,
    Math.floor(readPayloadNumber(action.payload, 'sharePrice')),
  );
  const companyMaxAffordableShares = Math.max(
    0,
    Math.floor(
      readPayloadNumber(
        action.payload,
        'maxAffordableShares',
        companySharePrice > 0
          ? Math.floor((activePlayer?.balance ?? 0) / companySharePrice)
          : 0,
      ),
    ),
  );
  const companyMaxPurchasableShares = Math.max(
    0,
    Math.floor(
      readPayloadNumber(
        action.payload,
        'maxPurchasableShares',
        Math.min(companyAvailableShares, companyMaxAffordableShares),
      ),
    ),
  );
  const companyPurchaseCost = shareCount * companySharePrice;
  const canSubmitCompanyPurchase = Boolean(
    canAct &&
      !busy &&
      shareCount > 0 &&
      shareCount <= companyMaxPurchasableShares,
  );

  if (action.type === 'random_event' && randomCard) {
    const randomSign = readPayloadString(action.payload, 'sign', 'positive');
    const randomAmount = readPayloadNumber(action.payload, 'amount');
    const randomBalanceBefore = readPayloadNumber(
      action.payload,
      'balanceBefore',
      activePlayer?.balance ?? 0,
    );
    const randomBalanceAfter = randomBalanceBefore + randomAmount;
    const isPositiveRandom = randomSign !== 'negative';

    return (
      <div className="pointer-events-none fixed inset-0 z-50 flex items-center justify-center bg-transparent p-[clamp(10px,4vw,40px)]">
        <section className="pointer-events-auto relative max-h-[calc(100dvh-20px)] w-full max-w-[640px] overflow-y-auto rounded-[24px] border border-lime-100/70 bg-emerald-900 text-white shadow-[0_28px_90px_rgba(2,44,34,0.58),0_0_42px_rgba(74,222,128,0.22)] ring-1 ring-white/25 sm:max-h-[calc(100dvh-48px)]">
          <div className="absolute inset-0 bg-[linear-gradient(145deg,_#d9f99d_0%,_#86efac_32%,_#22c55e_64%,_#166534_100%)]" />
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_top,_rgba(255,255,255,0.38),_transparent_38%),linear-gradient(to_bottom,_rgba(15,23,42,0.05),_rgba(15,23,42,0.46))]" />

          <div className="relative z-10 space-y-5 p-[clamp(16px,4vw,28px)]">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0 rounded-md bg-emerald-950/45 px-3 py-2 shadow-lg shadow-emerald-950/25 backdrop-blur-sm">
                <p className="text-xs font-semibold uppercase tracking-normal text-lime-100">
                  Картка випадку
                </p>
                <h2 className="mt-1 text-3xl font-bold tracking-normal text-white">
                  Random
                </h2>
              </div>
              <span
                className={joinClassNames(
                  'shrink-0 rounded px-2 py-1 text-xs font-bold shadow-sm',
                  isPositiveRandom
                    ? 'bg-white/95 text-emerald-800'
                    : 'bg-rose-50 text-rose-800',
                )}
              >
                {formatRandomSign(randomSign)}
              </span>
            </div>

            <div className="rounded-[20px] border border-white/45 bg-[#f8fff7]/95 p-[clamp(14px,3vw,22px)] text-[#10231b] shadow-2xl shadow-emerald-950/25 backdrop-blur-md">
              <div className="relative mx-auto aspect-[4/3] w-full max-w-[360px] overflow-hidden rounded-md bg-emerald-50 shadow-lg shadow-emerald-950/20">
                <Image
                  alt={randomCard.alt}
                  className="object-contain p-2"
                  fill
                  priority
                  sizes="360px"
                  src={randomCard.imageSrc}
                />
              </div>

              <div className="mt-4 rounded-[16px] border border-emerald-200/75 bg-white/92 px-4 py-4 text-center shadow-[0_12px_32px_rgba(6,78,59,0.12)]">
                <p className="text-xs font-black uppercase tracking-normal text-[#047857]">
                  {randomCard.title}
                </p>
                <h3
                  className={joinClassNames(
                    'mt-1 text-xl font-black tracking-normal',
                    isPositiveRandom ? 'text-[#065f46]' : 'text-[#be123c]',
                  )}
                >
                  {formatRandomSign(randomSign)}
                </h3>
                <p className="mx-auto mt-2 max-w-[430px] text-sm font-bold leading-6 text-[#243447]">
                  {isPositiveRandom
                    ? randomCard.positiveText
                    : randomCard.negativeText}
                </p>
              </div>

              <div className="mt-4 grid grid-cols-2 gap-2 text-center">
                <div
                  className={joinClassNames(
                    'rounded-md px-3 py-3 shadow-sm',
                    isPositiveRandom
                      ? 'bg-[#ecfdf5] text-[#065f46]'
                      : 'bg-[#fff1f2] text-[#be123c]',
                  )}
                >
                  <p className="text-[11px] font-bold uppercase tracking-normal">
                    Сума
                  </p>
                  <p className="mt-1 text-lg font-black">
                    {randomAmount > 0 ? '+' : ''}
                    {formatMoney(randomAmount)}
                  </p>
                </div>
                <div className="rounded-md bg-[#202335] px-3 py-3 text-white shadow-sm">
                  <p className="text-[11px] font-bold uppercase tracking-normal text-[#c8c8d8]">
                    Баланс після
                  </p>
                  <p
                    className={joinClassNames(
                      'mt-1 text-lg font-black',
                      randomBalanceAfter < 0 ? 'text-[#fb155f]' : 'text-[#f8fff7]',
                    )}
                  >
                    {formatMoney(randomBalanceAfter)}
                  </p>
                </div>
              </div>

              {randomBalanceAfter < 0 ? (
                <p className="mt-4 rounded-md bg-rose-50 px-3 py-2 text-center text-xs font-bold text-rose-700">
                  Після цього випадку борг збільшиться або зʼявиться новий.
                </p>
              ) : null}

              <button
                className="mt-5 h-11 w-full rounded-md bg-emerald-700 px-3 text-sm font-semibold text-white shadow-lg shadow-emerald-950/20 transition hover:bg-emerald-800 disabled:cursor-not-allowed disabled:bg-slate-300"
                disabled={!canAct || busy}
                onClick={() =>
                  runRpc('resolve_random_event', {
                    p_decision: 'confirm',
                    p_game_id: gameState.gameId,
                  })
                }
                type="button"
              >
                Далі
              </button>

              {error ? (
                <p
                  aria-live="polite"
                  className="mt-4 rounded-md bg-rose-50 px-3 py-2 text-sm font-semibold text-rose-700 shadow-sm"
                >
                  {error}
                </p>
              ) : null}
            </div>
          </div>
        </section>
      </div>
    );
  }

  if (action.type === 'negative_reputation') {
    return (
      <div className="pointer-events-none fixed inset-0 z-50 flex items-center justify-center bg-transparent px-4 py-6">
        <section className="negative-readable pointer-events-auto relative max-h-[calc(100vh-2rem)] w-full max-w-[560px] overflow-y-auto rounded-md border border-rose-200/70 bg-slate-950 text-white shadow-2xl shadow-rose-950/45 ring-1 ring-white/25">
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_top,_rgba(244,63,94,0.35),_transparent_34%),linear-gradient(145deg,_rgba(15,23,42,0.98),_rgba(127,29,29,0.9))]" />
          <div className="absolute inset-x-0 top-0 h-1 bg-gradient-to-r from-rose-500 via-red-300 to-slate-700" />

          <div className="relative z-10 space-y-5 p-5">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="text-xs font-semibold uppercase tracking-normal text-rose-200">
                  Репутаційний удар
                </p>
                <h2 className="mt-1 text-3xl font-bold tracking-normal text-white">
                  Негативна репутація
                </h2>
              </div>
              <span className="shrink-0 rounded bg-white/95 px-2 py-1 text-xs font-bold text-slate-800 shadow-sm">
                {canAct ? 'Ваш хід' : isActiveAction ? 'Перегляд' : 'Очікування'}
              </span>
            </div>

            <div className="rounded-md border border-white/15 bg-slate-950/70 p-4 shadow-2xl shadow-slate-950/35">
              <div className="grid gap-4 sm:grid-cols-[120px_minmax(0,1fr)] sm:items-center">
                <D6Face
                  rolling={busy && reputationPhase === 'initial'}
                  value={reputationDie || null}
                />

                <div className="min-w-0 space-y-3">
                  <p className="rounded-md border border-rose-200/25 bg-slate-950/80 px-3 py-2 text-sm font-semibold leading-6 text-rose-50 shadow-inner shadow-slate-950/40">
                    Киньте d6. Скільки випаде на кубику, стільки іміджу
                    гравець втрачає.
                  </p>

                  <div className="grid grid-cols-2 gap-2 text-center">
                    <div className="rounded-md bg-white/95 px-3 py-3 text-slate-950 shadow-sm ring-1 ring-white/70">
                      <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                        Імідж
                      </p>
                      <p className="mt-1 text-lg font-black">
                        {formatInteger(reputationImageBefore)}
                      </p>
                    </div>
                    <div className="rounded-md bg-white/95 px-3 py-3 text-slate-950 shadow-sm ring-1 ring-white/70">
                      <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                        d6
                      </p>
                      <p className="mt-1 text-lg font-black text-rose-700">
                        {reputationDie || '?'}
                      </p>
                    </div>
                  </div>
                </div>
              </div>

              {reputationReadyToConfirm ? (
                <div className="mt-4 grid grid-cols-2 gap-2 text-center">
                  <div className="rounded-md bg-rose-50 px-3 py-2 text-rose-800 shadow-sm">
                    <p className="text-[11px] font-bold uppercase tracking-normal">
                      Втрата іміджу
                    </p>
                    <p className="mt-1 text-lg font-black">
                      -{formatInteger(reputationImageLoss)}
                    </p>
                  </div>
                  <div className="rounded-md bg-white/95 px-3 py-2 text-slate-950 shadow-sm">
                    <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                      Після удару
                    </p>
                    <p
                      className={joinClassNames(
                        'mt-1 text-lg font-black',
                        reputationImageAfter < 0 ? 'text-rose-700' : 'text-slate-950',
                      )}
                    >
                      {formatInteger(reputationImageAfter)}
                    </p>
                  </div>
                </div>
              ) : null}

              <div className="mt-5">
                {reputationReadyToConfirm ? (
                  <button
                    className="h-11 w-full rounded-md bg-rose-600 px-3 text-sm font-semibold text-white shadow-lg shadow-rose-950/25 transition hover:bg-rose-700 disabled:cursor-not-allowed disabled:bg-slate-300"
                    disabled={!canAct || busy}
                    onClick={() =>
                      runRpc('resolve_negative_reputation', {
                        p_decision: 'confirm',
                        p_game_id: gameState.gameId,
                      })
                    }
                    type="button"
                  >
                    Далі
                  </button>
                ) : (
                  <button
                    className="h-11 w-full rounded-md bg-rose-600 px-3 text-sm font-semibold text-white shadow-lg shadow-rose-950/25 transition hover:bg-rose-700 disabled:cursor-not-allowed disabled:bg-slate-300"
                    disabled={!canAct || busy || !reputationCanStart}
                    onClick={() =>
                      runRpc('resolve_negative_reputation', {
                        p_decision: 'roll',
                        p_game_id: gameState.gameId,
                      })
                    }
                    type="button"
                  >
                    {busy ? 'Крутимо...' : 'Старт'}
                  </button>
                )}
              </div>

              {error ? (
                <p
                  aria-live="polite"
                  className="mt-4 rounded-md bg-white/95 px-3 py-2 text-sm font-semibold text-rose-700 shadow-sm"
                >
                  {error}
                </p>
              ) : null}
            </div>
          </div>
        </section>
      </div>
    );
  }

  if (action.type === 'deal_decision') {
    return (
      <div className="pointer-events-none fixed inset-0 z-50 flex items-center justify-center bg-transparent px-4 py-6">
        <section className="deal-readable pointer-events-auto relative max-h-[calc(100vh-2rem)] w-full max-w-[640px] overflow-y-auto rounded-md border border-white/50 bg-rose-950 text-white shadow-2xl shadow-rose-950/40 ring-1 ring-white/30">
          <div className="absolute inset-0">
            <Image
              alt="Ділова зустріч"
              className="object-cover"
              fill
              priority
              sizes="640px"
              src="/deal-cards/deal.jpg"
            />
          </div>
          <div className="absolute inset-0 bg-gradient-to-b from-rose-950/10 via-rose-950/25 to-slate-950/85" />

          <div className="relative z-10 flex min-h-[500px] flex-col justify-between p-5">
            <div className="flex items-start justify-between gap-3">
              <div className="rounded-md bg-slate-950/55 px-3 py-2 shadow-lg shadow-slate-950/25 backdrop-blur-sm">
                <p className="text-xs font-semibold uppercase tracking-normal text-rose-100">
                  Картка зустрічі
                </p>
                <h2 className="mt-1 text-3xl font-bold tracking-normal text-white">
                  Ділова зустріч
                </h2>
              </div>
              <span className="shrink-0 rounded bg-white/95 px-2 py-1 text-xs font-bold text-slate-800 shadow-sm">
                {canAct ? 'Ваш хід' : isActiveAction ? 'Перегляд' : 'Очікування'}
              </span>
            </div>

            <div className="rounded-md border border-white/25 bg-slate-950/78 p-4 shadow-2xl shadow-slate-950/35 backdrop-blur-sm">
              {dealPhase === 'initial' ? (
                <div className="space-y-4">
                  <div>
                    <h3 className="text-xl font-bold tracking-normal text-white">
                      Погодитись на зустріч?
                    </h3>
                    <p className="mt-2 text-sm font-semibold leading-6 text-rose-50">
                      Коефіцієнт додається до кидка d20. Якщо сума не перевищує
                      ваш імідж, зустріч успішна.
                    </p>
                  </div>

                  <div className="grid grid-cols-3 gap-2 text-center">
                    <div className="rounded-md bg-white/95 px-3 py-2 text-slate-950 shadow-sm">
                      <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                        Коефіцієнт
                      </p>
                      <p className="mt-1 text-base font-bold text-rose-700">
                        {formatInteger(dealCoefficient)}
                      </p>
                    </div>
                    <div className="rounded-md bg-white/95 px-3 py-2 text-slate-950 shadow-sm">
                      <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                        Імідж
                      </p>
                      <p className="mt-1 text-base font-bold">
                        {formatInteger(dealImage)}
                      </p>
                    </div>
                    <div className="rounded-md bg-white/95 px-3 py-2 text-slate-950 shadow-sm">
                      <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                        Ціна бала
                      </p>
                      <p className="mt-1 text-base font-bold">
                        {formatMoney(dealUnitValue)}
                      </p>
                    </div>
                  </div>

                  <D20Dice rolling={busy && canAct} />

                  <div className="grid grid-cols-2 gap-2">
                    <button
                      className="h-11 rounded-md bg-emerald-600 px-3 text-sm font-semibold text-white shadow-lg shadow-emerald-950/20 transition hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-slate-300 disabled:shadow-none"
                      disabled={!canAct || busy}
                      onClick={() =>
                        runRpc('resolve_deal', {
                          p_decision: 'roll',
                          p_game_id: gameState.gameId,
                        })
                      }
                      type="button"
                    >
                      {busy ? 'Кидаємо...' : 'Згода'}
                    </button>
                    <button
                      className="h-11 rounded-md border border-white/70 bg-white/95 px-3 text-sm font-semibold text-slate-800 shadow-lg shadow-slate-950/20 transition hover:bg-white disabled:cursor-not-allowed disabled:border-white/30 disabled:bg-white/40 disabled:text-white/70 disabled:shadow-none"
                      disabled={!canAct || busy}
                      onClick={() =>
                        runRpc('resolve_deal', {
                          p_decision: 'decline',
                          p_game_id: gameState.gameId,
                        })
                      }
                      type="button"
                    >
                      Відмова
                    </button>
                  </div>
                </div>
              ) : null}

              {dealPhase === 'rolled' ? (
                <div className="space-y-4">
                  <div>
                    <h3 className="text-xl font-bold tracking-normal text-white">
                      Результат зустрічі
                    </h3>
                    <p className="mt-2 text-sm font-semibold leading-6 text-rose-50">
                      Score = коефіцієнт {formatInteger(dealCoefficient)} + d20{' '}
                      {formatInteger(dealDie)} = {formatInteger(dealScore)}.
                    </p>
                  </div>

                  <D20Dice value={dealDie} />

                  <div className="grid grid-cols-3 gap-2 text-center">
                    <div className="rounded-md bg-white/95 px-3 py-2 text-slate-950 shadow-sm">
                      <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                        Імідж
                      </p>
                      <p className="mt-1 text-base font-bold">
                        {formatInteger(dealImage)}
                      </p>
                    </div>
                    <div className="rounded-md bg-white/95 px-3 py-2 text-slate-950 shadow-sm">
                      <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                        Різниця
                      </p>
                      <p
                        className={joinClassNames(
                          'mt-1 text-base font-bold',
                          dealDifference >= 0 ? 'text-emerald-700' : 'text-rose-700',
                        )}
                      >
                        {dealDifference > 0 ? '+' : ''}
                        {formatInteger(dealDifference)}
                      </p>
                    </div>
                    <div className="rounded-md bg-white/95 px-3 py-2 text-slate-950 shadow-sm">
                      <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                        Баланс
                      </p>
                      <p
                        className={joinClassNames(
                          'mt-1 text-base font-bold',
                          dealAmount >= 0 ? 'text-emerald-700' : 'text-rose-700',
                        )}
                      >
                        {dealAmount > 0 ? '+' : ''}
                        {formatMoney(dealAmount)}
                      </p>
                    </div>
                  </div>

                  <p
                    className={joinClassNames(
                      'rounded-md px-3 py-2 text-center text-sm font-bold shadow-sm',
                      dealSuccessful
                        ? 'bg-emerald-50 text-emerald-800'
                        : 'bg-rose-50 text-rose-800',
                    )}
                  >
                    {dealSuccessful
                      ? 'Зустріч успішна. Виграш буде додано після підтвердження.'
                      : 'Зустріч провалена. Сума буде списана після підтвердження.'}
                  </p>

                  <button
                    className="h-11 w-full rounded-md bg-emerald-600 px-3 text-sm font-semibold text-white shadow-lg shadow-emerald-950/20 transition hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-slate-300"
                    disabled={!canAct || busy}
                    onClick={() =>
                      runRpc('resolve_deal', {
                        p_decision: 'confirm',
                        p_game_id: gameState.gameId,
                      })
                    }
                    type="button"
                  >
                    Підтвердити
                  </button>
                </div>
              ) : null}

              {error ? (
                <p
                  aria-live="polite"
                  className="mt-4 rounded-md bg-white/95 px-3 py-2 text-sm font-semibold text-rose-700 shadow-sm"
                >
                  {error}
                </p>
              ) : null}
            </div>
          </div>
        </section>
      </div>
    );
  }

  if (action.type === 'casino_bet') {
    return (
      <div className="pointer-events-none fixed inset-0 z-50 flex items-center justify-center bg-transparent px-4 py-6">
        <section className="casino-readable pointer-events-auto relative max-h-[calc(100vh-2rem)] w-full max-w-[620px] overflow-y-auto rounded-md border border-amber-100/70 bg-slate-950 text-white shadow-2xl shadow-amber-950/40 ring-1 ring-white/25">
          <div className="absolute inset-0">
            <Image
              alt="Казино"
              className="object-cover"
              fill
              priority
              sizes="620px"
              src="/casino-cards/casino.jpg"
            />
          </div>
          <div className="absolute inset-0 bg-gradient-to-b from-slate-950/25 via-slate-950/20 to-slate-950/85" />
          <div className="relative z-10 flex min-h-[620px] flex-col justify-between p-5">
            <div className="flex items-start justify-between gap-3">
              <div className="rounded-md bg-slate-950/55 px-3 py-2 shadow-lg shadow-slate-950/25 backdrop-blur-sm">
                <p className="text-xs font-semibold uppercase tracking-normal text-amber-200">
                  Картка казино
                </p>
                <h2 className="mt-1 text-3xl font-bold tracking-normal text-white">
                  Казино
                </h2>
              </div>
              <span className="shrink-0 rounded bg-white/95 px-2 py-1 text-xs font-bold text-slate-800 shadow-sm">
                {canAct ? 'Ваш хід' : isActiveAction ? 'Перегляд' : 'Очікування'}
              </span>
            </div>

            <div className="rounded-md border border-white/20 bg-slate-950/75 p-4 shadow-2xl shadow-slate-950/35 backdrop-blur-sm">
              {casinoStep === 'intro' && casinoPhase === 'initial' ? (
                <div className="space-y-4">
                  <div>
                    <h3 className="text-xl font-bold tracking-normal text-white">
                      Зіграти на парне чи непарне?
                    </h3>
                    <p className="mt-2 text-sm font-semibold leading-6 text-slate-100">
                      Ви можете відмовитись і передати хід далі або прийняти
                      гру, зробити ставку та обрати результат суми двох кубиків.
                    </p>
                  </div>
                  <div className="grid grid-cols-2 gap-2 text-center">
                    <div className="rounded-md bg-white/95 px-3 py-2 text-slate-950">
                      <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                        Баланс
                      </p>
                      <p className="mt-1 text-base font-bold">
                        {formatMoney(casinoBalance)}
                      </p>
                    </div>
                    <div className="rounded-md bg-white/95 px-3 py-2 text-slate-950">
                      <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                        Множник
                      </p>
                      <p className="mt-1 text-base font-bold text-amber-700">
                        x2-x10
                      </p>
                    </div>
                  </div>
                  {casinoBalance < 0 ? (
                    <p className="rounded-md bg-amber-100/95 px-3 py-2 text-center text-xs font-bold text-amber-900">
                      Казино без ліміту: ставка може збільшити борг у разі програшу.
                    </p>
                  ) : null}
                  <div className="grid grid-cols-2 gap-2">
                    <button
                      className="h-11 rounded-md bg-amber-500 px-3 text-sm font-semibold text-slate-950 shadow-lg shadow-amber-950/20 transition hover:bg-amber-400 disabled:cursor-not-allowed disabled:bg-slate-300"
                      disabled={!canAct || busy}
                      onClick={() => setCasinoStep('bet')}
                      type="button"
                    >
                      Погодитись
                    </button>
                    <button
                      className="h-11 rounded-md border border-white/70 bg-white/95 px-3 text-sm font-semibold text-slate-800 shadow-lg shadow-slate-950/20 transition hover:bg-white disabled:cursor-not-allowed disabled:border-white/30 disabled:bg-white/40 disabled:text-white/70"
                      disabled={!canAct || busy}
                      onClick={() =>
                        runRpc('resolve_casino_bet', {
                          p_bet_amount: null,
                          p_decision: 'decline',
                          p_game_id: gameState.gameId,
                          p_parity: null,
                        })
                      }
                      type="button"
                    >
                      Відмова
                    </button>
                  </div>
                </div>
              ) : null}

              {casinoStep === 'bet' && casinoPhase === 'initial' ? (
                <div className="space-y-4">
                  <div>
                    <h3 className="text-xl font-bold tracking-normal text-white">
                      Ставка та прогноз
                    </h3>
                    <p className="mt-2 text-sm font-semibold leading-6 text-slate-100">
                      Оберіть будь-яку суму і вгадайте, парною чи непарною буде сума двох кубиків.
                    </p>
                  </div>

                  <label className="block">
                    <span className="text-xs font-bold uppercase tracking-normal text-amber-200">
                      Сума ставки
                    </span>
                    <input
                      className="mt-2 h-11 w-full rounded-md border border-white/30 bg-white/95 px-3 text-sm font-bold text-slate-950 outline-none transition focus:border-amber-400 focus:ring-4 focus:ring-amber-200/40"
                      inputMode="numeric"
                      min={0}
                      onChange={(event) => setCasinoBetInput(event.target.value)}
                      type="number"
                      value={casinoBetInput}
                    />
                  </label>

                  <div className="grid grid-cols-2 gap-2">
                    {(['even', 'odd'] as CasinoParity[]).map((parity) => (
                      <button
                        aria-pressed={casinoParity === parity}
                        className={joinClassNames(
                          'h-11 rounded-md border px-3 text-sm font-bold transition',
                          casinoParity === parity
                            ? 'border-amber-300 bg-amber-400 text-slate-950 shadow-lg shadow-amber-950/20'
                            : 'border-white/40 bg-white/15 text-white hover:bg-white/25',
                        )}
                        disabled={!canAct || busy}
                        key={parity}
                        onClick={() => setCasinoParity(parity)}
                        type="button"
                      >
                        {formatCasinoParity(parity)}
                      </button>
                    ))}
                  </div>

                  {!isCasinoBetValid ? (
                    <p className="rounded-md bg-white/95 px-3 py-2 text-center text-xs font-bold text-rose-700">
                      Введіть ставку 0 USD або більше.
                    </p>
                  ) : null}

                  <div className="grid grid-cols-2 gap-2">
                    <button
                      className="h-11 rounded-md bg-amber-500 px-3 text-sm font-semibold text-slate-950 shadow-lg shadow-amber-950/20 transition hover:bg-amber-400 disabled:cursor-not-allowed disabled:bg-slate-300"
                      disabled={!canSubmitCasinoBet}
                      onClick={() =>
                        runRpc('resolve_casino_bet', {
                          p_bet_amount: casinoBetAmount,
                          p_decision: 'roll',
                          p_game_id: gameState.gameId,
                          p_parity: casinoParity,
                        })
                      }
                      type="button"
                    >
                      {busy ? 'Кидаємо...' : 'Кинути кубики'}
                    </button>
                    <button
                      className="h-11 rounded-md border border-white/70 bg-white/95 px-3 text-sm font-semibold text-slate-800 shadow-lg shadow-slate-950/20 transition hover:bg-white disabled:cursor-not-allowed disabled:border-white/30 disabled:bg-white/40 disabled:text-white/70"
                      disabled={!canAct || busy}
                      onClick={() =>
                        runRpc('resolve_casino_bet', {
                          p_bet_amount: null,
                          p_decision: 'decline',
                          p_game_id: gameState.gameId,
                          p_parity: null,
                        })
                      }
                      type="button"
                    >
                      Відмова
                    </button>
                  </div>
                </div>
              ) : null}

              {casinoPhase !== 'initial' ? (
                <div className="space-y-4">
                  <div>
                    <h3 className="text-xl font-bold tracking-normal text-white">
                      Результат ставки
                    </h3>
                    <p className="mt-2 text-sm font-semibold leading-6 text-slate-100">
                      Ставка {formatMoney(casinoStoredBet)} на{' '}
                      {formatCasinoParity(casinoStoredParity).toLowerCase()}.
                    </p>
                  </div>

                  <div className="grid grid-cols-3 gap-2 text-center">
                    <div className="rounded-md bg-white/95 px-3 py-2 text-slate-950">
                      <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                        Кубики
                      </p>
                      <p className="mt-1 text-base font-bold">
                        {casinoHasDice ? `${casinoDice[0]} + ${casinoDice[1]}` : '? + ?'}
                      </p>
                    </div>
                    <div className="rounded-md bg-white/95 px-3 py-2 text-slate-950">
                      <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                        Сума
                      </p>
                      <p className="mt-1 text-base font-bold">
                        {casinoTotal || '?'}
                      </p>
                    </div>
                    <div className="rounded-md bg-white/95 px-3 py-2 text-slate-950">
                      <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                        Прогноз
                      </p>
                      <p className="mt-1 text-base font-bold text-amber-700">
                        {formatCasinoParity(casinoStoredParity)}
                      </p>
                    </div>
                  </div>

                  <p
                    className={joinClassNames(
                      'rounded-md px-3 py-2 text-center text-sm font-bold shadow-sm',
                      casinoWon
                        ? 'bg-emerald-50 text-emerald-800'
                        : 'bg-rose-50 text-rose-800',
                    )}
                  >
                    {casinoWon
                      ? 'Прогноз збігся. Запустіть коефіцієнт.'
                      : 'Прогноз не збігся. Банк забирає ставку.'}
                  </p>

                  {casinoWon ? (
                    <div className="rounded-md bg-slate-950/70 px-3 py-3">
                      <p className="text-center text-xs font-bold uppercase tracking-normal text-amber-200">
                        Коефіцієнт
                      </p>
                      <div className="mt-2 grid grid-cols-9 gap-1 text-center text-xs font-black text-slate-950">
                        {[2, 3, 4, 5, 6, 7, 8, 9, 10].map((multiplier) => (
                          <span
                            className={joinClassNames(
                              'rounded px-1 py-2',
                              casinoHasMultiplier && casinoMultiplier === multiplier
                                ? 'bg-emerald-300 ring-2 ring-white'
                                : busy && casinoCanLaunchMultiplier
                                  ? 'animate-pulse bg-amber-300'
                                  : 'bg-white/80',
                            )}
                            key={multiplier}
                          >
                            x{multiplier}
                          </span>
                        ))}
                      </div>
                    </div>
                  ) : null}

                  {casinoHasMultiplier ? (
                    <div className="grid grid-cols-2 gap-2 text-center">
                      <div className="rounded-md bg-white/95 px-3 py-2 text-slate-950">
                        <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                          Випав коефіцієнт
                        </p>
                        <p className="mt-1 text-base font-bold text-amber-700">
                          x{casinoMultiplier}
                        </p>
                      </div>
                      <div className="rounded-md bg-white/95 px-3 py-2 text-slate-950">
                        <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                          Виграш
                        </p>
                        <p className="mt-1 text-base font-bold text-emerald-700">
                          {formatMoney(casinoPayout)}
                        </p>
                      </div>
                    </div>
                  ) : null}

                  {casinoCanLaunchMultiplier ? (
                    <button
                      className="h-11 w-full rounded-md bg-amber-500 px-3 text-sm font-semibold text-slate-950 shadow-lg shadow-amber-950/20 transition hover:bg-amber-400 disabled:cursor-not-allowed disabled:bg-slate-300"
                      disabled={!canAct || busy}
                      onClick={() =>
                        runRpc('resolve_casino_bet', {
                          p_bet_amount: null,
                          p_decision: 'multiplier',
                          p_game_id: gameState.gameId,
                          p_parity: null,
                        })
                      }
                      type="button"
                    >
                      {busy ? 'Крутимо...' : 'Запустити коефіцієнт'}
                    </button>
                  ) : null}

                  {casinoCanCollect ? (
                    <button
                      className="h-11 w-full rounded-md bg-emerald-600 px-3 text-sm font-semibold text-white shadow-lg shadow-emerald-950/20 transition hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-slate-300"
                      disabled={!canAct || busy}
                      onClick={() =>
                        runRpc('resolve_casino_bet', {
                          p_bet_amount: null,
                          p_decision: 'collect',
                          p_game_id: gameState.gameId,
                          p_parity: null,
                        })
                      }
                      type="button"
                    >
                      {casinoWon ? 'Отримати' : 'Погодитись'}
                    </button>
                  ) : null}
                </div>
              ) : null}

              {error ? (
                <p
                  aria-live="polite"
                  className="mt-4 rounded-md bg-white/95 px-3 py-2 text-sm font-semibold text-rose-700 shadow-sm"
                >
                  {error}
                </p>
              ) : null}
            </div>
          </div>
        </section>
      </div>
    );
  }

  if (action.type === 'image_offer' && imageCard) {
    return (
      <div className="pointer-events-none fixed inset-0 z-50 flex items-center justify-center bg-transparent p-[clamp(10px,4vw,40px)]">
        <section
          className="image-readable pointer-events-auto relative isolate max-h-[calc(100dvh-20px)] w-full max-w-[720px] overflow-y-auto rounded-[22px] border border-white/35 bg-[#32105d] bg-center p-[clamp(18px,4vw,36px)] text-white shadow-[0_24px_70px_rgba(2,2,8,0.58),0_0_45px_rgba(192,132,252,0.22)] ring-1 ring-white/20 sm:max-h-[calc(100dvh-48px)] lg:max-h-[calc(100dvh-80px)]"
          style={{
            backgroundImage: "url('/image-cards/image-fon.jpg')",
            backgroundRepeat: 'no-repeat',
            backgroundSize: 'calc(100% + 96px) calc(100% + 96px)',
          }}
        >
          <div className="absolute inset-0 rounded-[22px] bg-gradient-to-br from-slate-950/24 via-fuchsia-950/8 to-slate-950/40" />
          <div className="relative z-10 space-y-5">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="text-xs font-semibold uppercase tracking-normal text-fuchsia-100">
                  Картка іміджу
                </p>
                <h2 className="mt-1 text-2xl font-bold tracking-normal text-white">
                  {imageCard.title}
                </h2>
              </div>
              <span className="shrink-0 rounded bg-white/95 px-2 py-1 text-xs font-bold text-slate-800 shadow-sm">
                {canAct ? 'Ваш хід' : isActiveAction ? 'Перегляд' : 'Очікування'}
              </span>
            </div>

            <div className="grid gap-4 sm:grid-cols-[220px_minmax(0,1fr)] sm:items-center">
              <div className="relative mx-auto aspect-[4/3] w-full max-w-[240px] overflow-hidden rounded-md bg-white/95 shadow-lg shadow-slate-950/25">
                <Image
                  alt={imageCard.alt}
                  className="object-contain p-2"
                  fill
                  sizes="240px"
                  src={imageCard.imageSrc}
                />
              </div>
              <div className="min-w-0 space-y-4">
                <p className="rounded-[16px] border border-white/18 bg-slate-950/52 px-4 py-3 text-sm font-bold leading-6 text-fuchsia-50 shadow-lg shadow-slate-950/25 backdrop-blur-sm">
                  {imageCard.description}
                </p>
                <div className="grid grid-cols-2 gap-2 text-center">
                  <div className="rounded-md bg-white/95 px-3 py-2 text-slate-950 shadow-sm">
                    <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                      Вартість
                    </p>
                    <p className="mt-1 text-base font-bold">
                      {formatMoney(imagePrice)}
                    </p>
                  </div>
                  <div className="rounded-md bg-white/95 px-3 py-2 text-slate-950 shadow-sm">
                    <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                      Імідж
                    </p>
                    <p className="mt-1 text-base font-bold text-emerald-700">
                      +{formatInteger(imageGain)}
                    </p>
                  </div>
                </div>
              </div>
            </div>

            {!canAffordImage ? (
              <p className="rounded-md bg-white/95 px-3 py-2 text-center text-xs font-bold text-rose-700 shadow-sm">
                Недостатньо коштів для цієї картки.
              </p>
            ) : null}

            <div className="grid grid-cols-2 gap-2">
              <button
                className="h-11 rounded-md bg-emerald-600 px-3 text-sm font-semibold text-white shadow-lg shadow-emerald-950/20 transition hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-slate-300 disabled:shadow-none"
                disabled={!canAct || busy || !canAffordImage}
                onClick={() =>
                  runRpc('resolve_image_offer', {
                    p_decision: 'accept',
                    p_game_id: gameState.gameId,
                  })
                }
                type="button"
              >
                Згоден
              </button>
              <button
                className="h-11 rounded-md border border-fuchsia-100/70 bg-slate-950/55 px-3 text-sm font-semibold text-fuchsia-50 shadow-lg shadow-slate-950/25 transition hover:border-white hover:bg-fuchsia-500/20 hover:text-white disabled:cursor-not-allowed disabled:border-white/25 disabled:bg-slate-950/25 disabled:text-slate-400 disabled:shadow-none"
                disabled={!canAct || busy}
                onClick={() =>
                  runRpc('resolve_image_offer', {
                    p_decision: 'decline',
                    p_game_id: gameState.gameId,
                  })
                }
                type="button"
              >
                Відмовитись
              </button>
            </div>

            {error ? (
              <p
                aria-live="polite"
                className="rounded-md bg-white/95 px-3 py-2 text-sm font-semibold text-rose-700 shadow-sm"
              >
                {error}
              </p>
            ) : null}
          </div>
        </section>
      </div>
    );
  }

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
          <div className="space-y-4 rounded-md border border-indigo-100 bg-indigo-50 p-4">
            <div>
              <p className="text-xs font-bold uppercase tracking-normal text-indigo-700">
                Компанія
              </p>
              <h3 className="mt-1 text-xl font-bold tracking-normal text-slate-950">
                {companyName}
              </h3>
            </div>

            <div className="grid gap-2 text-center sm:grid-cols-3">
              <div className="rounded-md bg-white px-3 py-2">
                <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                  1 акція
                </p>
                <p className="mt-1 text-sm font-bold text-slate-950">
                  {formatMoney(companySharePrice)}
                </p>
              </div>
              <div className="rounded-md bg-white px-3 py-2">
                <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                  Вільно
                </p>
                <p className="mt-1 text-sm font-bold text-emerald-700">
                  {formatInteger(companyAvailableShares)} /{' '}
                  {formatPercent(
                    getSharePercent(companyAvailableShares, companyTotalShares),
                  )}
                </p>
              </div>
              <div className="rounded-md bg-white px-3 py-2">
                <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                  Ваші акції
                </p>
                <p className="mt-1 text-sm font-bold text-indigo-700">
                  {formatInteger(companyPlayerShares)} /{' '}
                  {formatPercent(
                    getSharePercent(companyPlayerShares, companyTotalShares),
                  )}
                </p>
              </div>
            </div>

            <label className="block">
              <span className="text-xs font-bold uppercase tracking-normal text-slate-600">
                Кількість для покупки
              </span>
              <input
                className="mt-2 h-11 w-full rounded-md border border-slate-300 bg-white px-3 text-sm font-semibold outline-none transition focus:border-indigo-600 focus:ring-4 focus:ring-indigo-100"
                max={companyMaxPurchasableShares}
                min={0}
                onChange={(event) => {
                  const nextShareCount = Math.floor(
                    Number(event.target.value) || 0,
                  );

                  setShareCount(
                    Math.max(
                      0,
                      Math.min(companyMaxPurchasableShares, nextShareCount),
                    ),
                  );
                }}
                type="number"
                value={shareCount}
              />
            </label>

            <div className="rounded-md bg-white px-3 py-2 text-sm font-semibold text-slate-700">
              <p>
                Максимум зараз: {formatInteger(companyMaxPurchasableShares)} шт.
              </p>
              <p className="mt-1">
                Вартість покупки: {formatMoney(companyPurchaseCost)}
              </p>
            </div>

            <div className="grid gap-2 sm:grid-cols-2">
              <button
                className="h-11 rounded-md bg-indigo-600 px-3 text-sm font-semibold text-white transition hover:bg-indigo-700 disabled:cursor-not-allowed disabled:bg-slate-300"
                disabled={!canSubmitCompanyPurchase}
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
                className="h-11 rounded-md border border-slate-300 bg-white px-3 text-sm font-semibold text-slate-700 transition hover:bg-slate-50 disabled:cursor-not-allowed disabled:text-slate-300"
                disabled={!canAct || busy}
                onClick={() =>
                  runRpc('resolve_company', {
                    p_game_id: gameState.gameId,
                    p_share_count: 0,
                  })
                }
                type="button"
              >
                Не купляти
              </button>
            </div>
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
  const {
    applyStateSnapshot,
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
  const [botTurnError, setBotTurnError] = useState<string | null>(null);
  const [privatePlayerCardOpen, setPrivatePlayerCardOpen] = useState(false);
  const [privatePlayerSnapshot, setPrivatePlayerSnapshot] =
    useState<Player | null>(null);
  const [thinkingBotPlayerId, setThinkingBotPlayerId] =
    useState<PlayerId | null>(null);

  const basePrivatePlayer = useMemo(
    () =>
      currentPlayer
        ? players.find((player) => player.id === currentPlayer.id) ?? currentPlayer
        : null,
    [currentPlayer, players],
  );
  const privatePlayer = useMemo(() => {
    if (!basePrivatePlayer) {
      return null;
    }

    if (
      privatePlayerSnapshot?.id === basePrivatePlayer.id &&
      readPlayerTimestamp(privatePlayerSnapshot) >=
        readPlayerTimestamp(basePrivatePlayer)
    ) {
      return {
        ...basePrivatePlayer,
        ...privatePlayerSnapshot,
      };
    }

    return basePrivatePlayer;
  }, [basePrivatePlayer, privatePlayerSnapshot]);
  const boardPlayers = useMemo(
    () =>
      players.filter((player) => !player.eliminated).map((player) => ({
        avatarColor: player.avatarColor,
        avatarStyle: player.avatarStyle,
        cellId: player.cellId,
        id: player.id,
        name: player.name,
      })),
    [players],
  );
  const activeCellId =
    currentTurnPlayer?.cellId ?? privatePlayer?.cellId ?? players[0]?.cellId;
  const isActivePlayerTurn = Boolean(
    privatePlayer && gameState?.currentTurnPlayerId === privatePlayer.id,
  );
  const canControlActivePlayer = Boolean(
    privatePlayer && currentPlayer && privatePlayer.id === currentPlayer.id,
  );
  const diceDisabled =
    !gameState ||
    gameState.status !== 'in_progress' ||
    !isActivePlayerTurn ||
    !canControlActivePlayer ||
    Boolean(gameState.pendingAction);

  const handleActionResolved = useCallback(
    async (stateSnapshot?: unknown, playerSnapshot?: Player | null) => {
      let resolvedPlayerSnapshot = playerSnapshot ?? null;

      if (stateSnapshot) {
        const snapshotPlayer = readPlayerFromStateSnapshot(
          stateSnapshot,
          basePrivatePlayer?.id ?? currentPlayer?.id,
        );

        if (snapshotPlayer) {
          resolvedPlayerSnapshot = snapshotPlayer;
        }
      }

      if (resolvedPlayerSnapshot) {
        setPrivatePlayerSnapshot(resolvedPlayerSnapshot);
      }

      if (stateSnapshot) {
        applyStateSnapshot(stateSnapshot);
        window.setTimeout(() => {
          void refresh();
        }, 350);
        return;
      }

      await refresh();
    },
    [applyStateSnapshot, basePrivatePlayer?.id, currentPlayer?.id, refresh],
  );

  useEffect(() => {
    if (!privatePlayerSnapshot) {
      return;
    }

    if (!basePrivatePlayer || privatePlayerSnapshot.id !== basePrivatePlayer.id) {
      setPrivatePlayerSnapshot(null);
      return;
    }

    if (
      readPlayerTimestamp(basePrivatePlayer) >=
        readPlayerTimestamp(privatePlayerSnapshot) &&
      haveSamePlayerStats(basePrivatePlayer, privatePlayerSnapshot)
    ) {
      setPrivatePlayerSnapshot(null);
    }
  }, [basePrivatePlayer, privatePlayerSnapshot]);

  useEffect(() => {
    if (!privatePlayer) {
      setPrivatePlayerCardOpen(false);
    }
  }, [privatePlayer?.id]);

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

  return (
    <div className="min-h-screen text-slate-950">
      <SiteHeader
        extraLinks={[
          { href: `/lobby/${encodeURIComponent(joinCode)}`, label: 'Лобі' },
        ]}
        maxWidth="wide"
      />

      <main className="mx-auto w-full max-w-[1600px] px-4 py-6 sm:px-6">
        {loading ? (
          <section className="neo-panel rounded-[18px] border border-slate-200 bg-white p-6 shadow-sm">
            <p className="text-sm font-semibold text-slate-600">
              Завантажуємо гру...
            </p>
          </section>
        ) : null}

        {error ? (
          <section className="rounded-[18px] border border-rose-300/35 bg-rose-500/12 p-5 text-sm font-semibold text-rose-100">
            {error}
          </section>
        ) : null}

        {!loading && !gameState ? (
          <section className="neo-panel rounded-[18px] border border-slate-200 bg-white p-6 shadow-sm">
            <h1 className="text-2xl font-bold tracking-normal text-slate-950">
              Гру не знайдено
            </h1>
            <Link
              className="neo-button mt-5 inline-flex h-10 items-center justify-center rounded-[16px] bg-slate-950 px-4 text-sm font-semibold text-white transition hover:bg-slate-800"
              href="/#start"
            >
              На головну
            </Link>
          </section>
        ) : null}

        {gameState ? (
          <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_390px]">
            <section className="neo-panel rounded-[20px] border border-slate-200 bg-white p-4 shadow-sm xl:col-span-2">
              <div className="grid gap-4 xl:grid-cols-[minmax(0,1fr)_390px] xl:items-start">
                <div className="min-w-0">
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
                      <div className="neo-panel-pressed rounded-[16px] bg-slate-50 px-3 py-2">
                        <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                          Статус
                        </p>
                        <p className="mt-1 truncate text-sm font-bold text-slate-950">
                          {statusLabels[gameState.status]}
                        </p>
                      </div>
                      <div className="neo-panel-pressed rounded-[16px] bg-slate-50 px-3 py-2">
                        <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                          Гравці
                        </p>
                        <p className="mt-1 text-sm font-bold text-slate-950">
                          {players.length}/{gameState.maxPlayers}
                        </p>
                      </div>
                      <div className="neo-panel-pressed rounded-[16px] bg-slate-50 px-3 py-2">
                        <p className="text-[11px] font-bold uppercase tracking-normal text-slate-500">
                          Realtime
                        </p>
                        <p
                          className={joinClassNames(
                            'mt-1 truncate text-sm font-bold',
                            isRealtimeConnected
                              ? 'text-emerald-700'
                              : 'text-amber-700',
                          )}
                        >
                          {isRealtimeConnected ? 'Online' : 'Sync'}
                        </p>
                      </div>
                    </div>
                  </div>

                  {players.length > 0 ? (
                    <div className="mt-4 border-t border-violet-300/20 pt-4">
                      <SeatSwitcher
                        browserPlayerId={currentPlayer?.id ?? null}
                        currentTurnPlayerId={gameState.currentTurnPlayerId}
                        players={players}
                      />
                    </div>
                  ) : null}
                </div>

                <ConnectionStatus
                  className="h-full shadow-none"
                  isOnline={isBrowserOnline}
                  lastSyncedAt={lastSyncedAt}
                  onRefresh={refresh}
                  realtimeStatus={realtimeStatus}
                  refreshing={refreshing}
                />
              </div>
            </section>

            <div className="min-w-0 space-y-4">
              {gameState.status === 'lobby' ? (
                <section className="rounded-[18px] border border-amber-300/35 bg-amber-500/12 p-4 text-sm font-semibold text-amber-100">
                  Гра ще в лобі. Почати можна зі сторінки лобі.
                </section>
              ) : null}

              {gameState.status === 'finished' ? (
                <section className="rounded-[18px] border border-emerald-300/35 bg-emerald-500/12 p-4 text-sm font-semibold text-emerald-100">
                  Переможець:{' '}
                  {players.find((player) => player.id === gameState.winnerPlayerId)
                    ?.name ?? 'очікується'}
                </section>
              ) : null}

              <Board
                activeCellId={activeCellId}
                centerSlot={
                  <div className="mx-auto flex w-full max-w-[220px] flex-col items-center gap-2 lg:max-w-[300px]">
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
                    </div>

                    <Dice
                      className="w-full text-left shadow-none xl:hidden"
                      compact
                      currentTurnPlayerId={gameState.currentTurnPlayerId}
                      disabled={diceDisabled}
                      gameId={gameState.gameId}
                      isCurrentPlayerTurn={isActivePlayerTurn}
                      onRolled={refresh}
                      playerId={privatePlayer?.id ?? null}
                    />

                    {privatePlayer ? (
                      <button
                        className="neo-button inline-flex min-h-10 items-center justify-center rounded-[16px] bg-slate-950 px-3 py-2 text-xs font-bold text-white transition hover:bg-slate-800"
                        onClick={() => setPrivatePlayerCardOpen(true)}
                        type="button"
                      >
                        Карточка гравця
                      </button>
                    ) : null}
                  </div>
                }
                players={boardPlayers}
              />
            </div>

            <aside className="space-y-4 xl:sticky xl:top-4 xl:max-h-[calc(100vh-2rem)] xl:overflow-y-auto">
              <Dice
                className="hidden xl:block"
                currentTurnPlayerId={gameState.currentTurnPlayerId}
                disabled={diceDisabled}
                gameId={gameState.gameId}
                isCurrentPlayerTurn={isActivePlayerTurn}
                onRolled={refresh}
                playerId={privatePlayer?.id ?? null}
              />

              {privatePlayer ? (
                <button
                  className="neo-button h-11 w-full rounded-[16px] bg-slate-950 px-3 text-sm font-semibold text-white transition hover:bg-slate-800"
                  onClick={() => setPrivatePlayerCardOpen(true)}
                  type="button"
                >
                  Карточка гравця
                </button>
              ) : null}

              <PendingActionPanel
                action={gameState.pendingAction}
                activePlayer={privatePlayer}
                controllablePlayerId={currentPlayer?.id ?? null}
                gameState={gameState}
                onResolved={handleActionResolved}
              />

              {thinkingBotPlayerId || botTurnError ? (
                <section className="rounded-[18px] border border-amber-300/35 bg-amber-500/12 p-4 text-sm font-semibold text-amber-100">
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

        {gameState && privatePlayer ? (
          <PrivatePlayerStatsModal
            gameState={gameState}
            onClose={() => setPrivatePlayerCardOpen(false)}
            onPlayerUpdated={handleActionResolved}
            open={privatePlayerCardOpen}
            player={privatePlayer}
          />
        ) : null}
      </main>
    </div>
  );
}
