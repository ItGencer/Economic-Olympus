'use client';

import { useEffect, useState } from 'react';

import type { GameRealtimeStatus } from '@/hooks/useGameRealtime';

type ConnectionStatusProps = {
  className?: string;
  isOnline: boolean;
  lastSyncedAt?: string | null;
  onRefresh?: () => Promise<void> | void;
  realtimeStatus?: GameRealtimeStatus;
  refreshing?: boolean;
};

type ConnectionTone = 'good' | 'warning' | 'danger';

const timeFormatter = new Intl.DateTimeFormat('uk-UA', {
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
});

function joinClassNames(...classes: Array<string | false | null | undefined>) {
  return classes.filter(Boolean).join(' ');
}

function formatSyncTime(value?: string | null) {
  if (!value) {
    return 'немає';
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return 'немає';
  }

  return timeFormatter.format(date);
}

function getStatusMeta({
  isOnline,
  realtimeStatus,
  refreshing,
}: Pick<ConnectionStatusProps, 'isOnline' | 'realtimeStatus' | 'refreshing'>) {
  if (!isOnline) {
    return {
      label: 'Offline',
      message: 'Немає мережі',
      tone: 'danger' as ConnectionTone,
    };
  }

  if (refreshing) {
    return {
      label: 'Sync',
      message: 'Оновлення',
      tone: 'warning' as ConnectionTone,
    };
  }

  if (!realtimeStatus || realtimeStatus === 'subscribed') {
    return {
      label: 'Online',
      message: 'Realtime активний',
      tone: 'good' as ConnectionTone,
    };
  }

  if (realtimeStatus === 'connecting' || realtimeStatus === 'idle') {
    return {
      label: 'Sync',
      message: 'Підключення',
      tone: 'warning' as ConnectionTone,
    };
  }

  return {
    label: 'Reconnect',
    message: 'Потрібне оновлення',
    tone: 'danger' as ConnectionTone,
  };
}

export function ConnectionStatus({
  className,
  isOnline,
  lastSyncedAt,
  onRefresh,
  realtimeStatus,
  refreshing = false,
}: ConnectionStatusProps) {
  const [mounted, setMounted] = useState(false);
  const meta = mounted
    ? getStatusMeta({ isOnline, realtimeStatus, refreshing })
    : {
        label: 'Sync',
        message: 'Перевірка',
        tone: 'warning' as ConnectionTone,
      };
  const syncedAtLabel = mounted ? formatSyncTime(lastSyncedAt) : 'немає';

  useEffect(() => {
    setMounted(true);
  }, []);

  return (
    <section
      aria-label="Стан підключення"
      className={joinClassNames(
        'rounded-md border bg-white p-4 shadow-sm',
        meta.tone === 'good' && 'border-emerald-200',
        meta.tone === 'warning' && 'border-amber-200',
        meta.tone === 'danger' && 'border-rose-200',
        className,
      )}
    >
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <span
              className={joinClassNames(
                'h-2.5 w-2.5 rounded-full',
                !mounted && 'bg-slate-300',
                mounted && meta.tone === 'good' && 'bg-emerald-500',
                mounted && meta.tone === 'warning' && 'bg-amber-500',
                mounted && meta.tone === 'danger' && 'bg-rose-500',
              )}
            />
            <p className="truncate text-sm font-bold text-slate-950">
              {meta.label}
            </p>
          </div>
          <p className="mt-1 truncate text-xs font-semibold text-slate-500">
            {meta.message} · {syncedAtLabel}
          </p>
        </div>

        {onRefresh ? (
          <button
            className="h-9 shrink-0 rounded-md border border-slate-300 px-3 text-xs font-bold text-slate-700 transition hover:bg-slate-50 disabled:cursor-not-allowed disabled:text-slate-300"
            disabled={refreshing}
            onClick={() => void onRefresh()}
            type="button"
          >
            Оновити
          </button>
        ) : null}
      </div>
    </section>
  );
}

export default ConnectionStatus;
