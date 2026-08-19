'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import {
  ensurePlayableUser,
  getSupabaseClient,
  getSupabaseSetupErrorMessage,
  isSupabaseConfigured,
} from '@/lib/supabase';
import {
  normalizeAvatarColor,
  normalizeAvatarStyle,
} from '@/lib/playerAvatarConfig';
import type {
  GameId,
  GameLogEntry,
  GameState,
  GameStatus,
  Player,
  PlayerId,
} from '@/types';

const MAX_LOG_ENTRIES = 80;

type GameRow = {
  created_at: string;
  current_turn_player_id: string | null;
  id: string;
  join_code: string;
  max_players: number;
  state: unknown;
  status: GameStatus;
  updated_at: string;
  winner_player_id: string | null;
};

type GameLogRow = {
  created_at: string;
  event_type: string;
  game_id: string;
  id: string;
  message: string;
  payload: unknown;
  player_id: string | null;
  turn_number: number | null;
};

type LoadOptions = {
  silent?: boolean;
};

export type GameRealtimeStatus =
  | 'idle'
  | 'connecting'
  | 'subscribed'
  | 'closed'
  | 'channel_error'
  | 'timed_out';

export type UseGameRealtimeOptions = {
  enabled?: boolean;
  gameId?: GameId | null;
  initialState?: GameState | null;
  joinCode?: string | null;
};

export type UseGameRealtimeResult = {
  currentPlayer: Player | null;
  currentPlayerId: PlayerId | null;
  currentTurnPlayer: Player | null;
  error: string | null;
  gameState: GameState | null;
  isBrowserOnline: boolean;
  isRealtimeConnected: boolean;
  lastSyncedAt: string | null;
  loading: boolean;
  players: Player[];
  realtimeStatus: GameRealtimeStatus;
  applyStateSnapshot: (snapshot: unknown) => void;
  refresh: () => Promise<void>;
  refreshing: boolean;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isGameStatus(value: unknown): value is GameStatus {
  return value === 'lobby' || value === 'in_progress' || value === 'finished';
}

function readNullableString(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
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

function normalizeJoinCode(value?: string | null) {
  return value?.trim().toUpperCase() ?? null;
}

function readBrowserOnline() {
  return typeof navigator === 'undefined' ? true : navigator.onLine;
}

function readGameState(value: unknown): GameState | null {
  if (!isRecord(value)) {
    return null;
  }

  const players = Array.isArray(value.players)
    ? (value.players as Player[]).map((player) => ({
        ...player,
        avatarColor: normalizeAvatarColor(player.avatarColor),
        avatarStyle: normalizeAvatarStyle(player.avatarStyle),
        debtWarning: Boolean(player.debtWarning),
        eliminated: Boolean(player.eliminated),
      }))
    : [];

  if (
    typeof value.gameId !== 'string' ||
    !isGameStatus(value.status) ||
    typeof value.joinCode !== 'string' ||
    typeof value.maxPlayers !== 'number'
  ) {
    return null;
  }

  return {
    companies: isRecord(value.companies)
      ? (value.companies as GameState['companies'])
      : {},
    createdAt: typeof value.createdAt === 'string' ? value.createdAt : '',
    currentTurnPlayerId: readNullableString(value.currentTurnPlayerId),
    directors: isRecord(value.directors)
      ? (value.directors as GameState['directors'])
      : {},
    gameId: value.gameId,
    joinCode: value.joinCode,
    log: Array.isArray(value.log) ? (value.log as GameState['log']) : [],
    maxPlayers: value.maxPlayers,
    pendingAction: isRecord(value.pendingAction)
      ? (value.pendingAction as unknown as GameState['pendingAction'])
      : null,
    players,
    status: value.status,
    tenders: isRecord(value.tenders)
      ? (value.tenders as GameState['tenders'])
      : {},
    turn: isRecord(value.turn)
      ? (value.turn as unknown as GameState['turn'])
      : null,
    updatedAt: typeof value.updatedAt === 'string' ? value.updatedAt : '',
    winnerPlayerId: readNullableString(value.winnerPlayerId),
  };
}

function buildFallbackState(row: GameRow): GameState {
  return {
    companies: {},
    createdAt: row.created_at,
    currentTurnPlayerId: row.current_turn_player_id,
    directors: {},
    gameId: row.id,
    joinCode: row.join_code,
    log: [],
    maxPlayers: row.max_players,
    pendingAction: null,
    players: [],
    status: row.status,
    tenders: {},
    turn: null,
    updatedAt: row.updated_at,
    winnerPlayerId: row.winner_player_id,
  };
}

function readStateFromRow(row: GameRow): GameState {
  const state = readGameState(row.state) ?? buildFallbackState(row);
  const rowUpdatedAt = Date.parse(row.updated_at);
  const stateUpdatedAt = Date.parse(state.updatedAt);
  const updatedAt =
    !Number.isNaN(stateUpdatedAt) &&
    (Number.isNaN(rowUpdatedAt) || stateUpdatedAt >= rowUpdatedAt)
      ? state.updatedAt
      : row.updated_at;

  return {
    ...state,
    currentTurnPlayerId: row.current_turn_player_id,
    gameId: row.id,
    joinCode: row.join_code,
    maxPlayers: row.max_players,
    status: row.status,
    updatedAt,
    winnerPlayerId: row.winner_player_id,
  };
}

function readGameLogEntry(row: GameLogRow): GameLogEntry {
  return {
    createdAt: row.created_at,
    eventType: row.event_type,
    gameId: row.game_id,
    id: row.id,
    message: row.message,
    payload: isRecord(row.payload) ? row.payload : {},
    playerId: readNullableString(row.player_id) ?? undefined,
    turnNumber: typeof row.turn_number === 'number' ? row.turn_number : undefined,
  };
}

function readLogTimestamp(entry: GameLogEntry) {
  const timestamp = Date.parse(entry.createdAt);

  return Number.isNaN(timestamp) ? 0 : timestamp;
}

function readStateTimestamp(state: GameState | null) {
  if (!state) {
    return 0;
  }

  const updatedAt = Date.parse(state.updatedAt);

  if (!Number.isNaN(updatedAt)) {
    return updatedAt;
  }

  const createdAt = Date.parse(state.createdAt);

  return Number.isNaN(createdAt) ? 0 : createdAt;
}

function mergeFreshGameState(
  currentState: GameState | null,
  nextState: GameState,
) {
  if (
    currentState?.gameId === nextState.gameId &&
    readStateTimestamp(nextState) < readStateTimestamp(currentState)
  ) {
    return {
      ...currentState,
      log: nextState.log.length > 0 ? nextState.log : currentState.log,
    };
  }

  return nextState;
}

function mergeLogEntry(entries: GameLogEntry[], incoming: GameLogEntry) {
  if (entries.some((entry) => entry.id === incoming.id)) {
    return entries;
  }

  return [...entries, incoming]
    .sort((left, right) => readLogTimestamp(left) - readLogTimestamp(right))
    .slice(-MAX_LOG_ENTRIES);
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

export function useGameRealtime({
  enabled = true,
  gameId = null,
  initialState = null,
  joinCode = null,
}: UseGameRealtimeOptions): UseGameRealtimeResult {
  const normalizedJoinCode = useMemo(() => normalizeJoinCode(joinCode), [joinCode]);
  const [currentPlayerId, setCurrentPlayerId] = useState<PlayerId | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [gameState, setGameState] = useState<GameState | null>(initialState);
  const [isBrowserOnline, setIsBrowserOnline] = useState(readBrowserOnline);
  const [lastSyncedAt, setLastSyncedAt] = useState<string | null>(
    initialState?.updatedAt ?? null,
  );
  const [loading, setLoading] = useState(Boolean(enabled && !initialState));
  const [realtimeStatus, setRealtimeStatus] =
    useState<GameRealtimeStatus>('idle');
  const [refreshing, setRefreshing] = useState(false);
  const [resolvedGameId, setResolvedGameId] = useState<GameId | null>(
    initialState?.gameId ?? gameId,
  );
  const requestIdRef = useRef(0);

  useEffect(() => {
    if (!initialState) {
      return;
    }

    setGameState(initialState);
    setLastSyncedAt(new Date().toISOString());
    setResolvedGameId(initialState.gameId);
  }, [initialState]);

  const loadGameState = useCallback(
    async ({ silent = false }: LoadOptions = {}) => {
      const targetGameId = gameId ?? (normalizedJoinCode ? null : resolvedGameId);
      const requestId = requestIdRef.current + 1;

      requestIdRef.current = requestId;

      if (!enabled || (!targetGameId && !normalizedJoinCode)) {
        setLoading(false);
        return;
      }

      if (!isSupabaseConfigured()) {
        setError(getSupabaseSetupErrorMessage());
        setLoading(false);
        setRefreshing(false);
        return;
      }

      if (silent) {
        setRefreshing(true);
      } else {
        setLoading(true);
      }

      setError(null);

      try {
        const user = await ensurePlayableUser();
        const supabase = getSupabaseClient();
        let query = supabase
          .from('games')
          .select(
            'id,status,join_code,max_players,state,current_turn_player_id,winner_player_id,created_at,updated_at',
          );

        query = targetGameId
          ? query.eq('id', targetGameId)
          : query.eq('join_code', normalizedJoinCode);

        const { data, error: gameError } = await query.maybeSingle();

        if (gameError) {
          throw gameError;
        }

        if (requestId !== requestIdRef.current) {
          return;
        }

        setCurrentPlayerId(user.id);

        if (!data) {
          setGameState(null);
          setLastSyncedAt(new Date().toISOString());
          setResolvedGameId(null);
          return;
        }

        const nextState = readStateFromRow(data as GameRow);
        const { data: logData, error: logError } = await supabase
          .from('game_log')
          .select(
            'id,game_id,turn_number,player_id,event_type,message,payload,created_at',
          )
          .eq('game_id', nextState.gameId)
          .order('created_at', { ascending: false })
          .limit(MAX_LOG_ENTRIES);

        if (logError) {
          throw logError;
        }

        if (requestId !== requestIdRef.current) {
          return;
        }

        const log = ((logData ?? []) as GameLogRow[])
          .map(readGameLogEntry)
          .reverse();

        setGameState((currentState) => mergeFreshGameState(currentState, {
          ...nextState,
          log,
        }));
        setLastSyncedAt(new Date().toISOString());
        setResolvedGameId(nextState.gameId);
      } catch (caughtError) {
        if (requestId === requestIdRef.current) {
          setError(readErrorMessage(caughtError));
        }
      } finally {
        if (requestId === requestIdRef.current) {
          setLoading(false);
          setRefreshing(false);
        }
      }
    },
    [enabled, gameId, normalizedJoinCode, resolvedGameId],
  );

  useEffect(() => {
    void loadGameState();
  }, [loadGameState]);

  useEffect(() => {
    if (!enabled) {
      return;
    }

    function handleOnline() {
      setIsBrowserOnline(true);
      void loadGameState({ silent: true });
    }

    function handleOffline() {
      setIsBrowserOnline(false);
    }

    function handleVisibilityChange() {
      if (document.visibilityState === 'visible') {
        void loadGameState({ silent: true });
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
  }, [enabled, loadGameState]);

  useEffect(() => {
    if (!enabled || !resolvedGameId) {
      setRealtimeStatus('idle');
      return;
    }

    if (!isSupabaseConfigured()) {
      setRealtimeStatus('closed');
      return;
    }

    const supabase = getSupabaseClient();
    const channel = supabase
      .channel(`game:${resolvedGameId}`)
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          filter: `id=eq.${resolvedGameId}`,
          schema: 'public',
          table: 'games',
        },
        (payload) => {
          const nextState = readStateFromRow(payload.new as GameRow);

          setGameState((currentState) =>
            mergeFreshGameState(currentState, {
              ...nextState,
              log:
                currentState?.gameId === nextState.gameId
                  ? currentState.log
                  : nextState.log,
            }),
          );
          setLastSyncedAt(new Date().toISOString());
        },
      )
      .on(
        'postgres_changes',
        {
          event: '*',
          filter: `game_id=eq.${resolvedGameId}`,
          schema: 'public',
          table: 'players',
        },
        () => {
          void loadGameState({ silent: true });
        },
      )
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          filter: `game_id=eq.${resolvedGameId}`,
          schema: 'public',
          table: 'game_log',
        },
        (payload) => {
          const entry = readGameLogEntry(payload.new as GameLogRow);

          setGameState((currentState) => {
            if (!currentState || currentState.gameId !== resolvedGameId) {
              return currentState;
            }

            return {
              ...currentState,
              log: mergeLogEntry(currentState.log, entry),
            };
          });
          setLastSyncedAt(new Date().toISOString());
        },
      )
      .subscribe((status) => {
        const nextStatus = toRealtimeStatus(status);

        setRealtimeStatus(nextStatus);

        if (nextStatus === 'channel_error' || nextStatus === 'timed_out') {
          void loadGameState({ silent: true });
        }
      });

    setRealtimeStatus('connecting');

    return () => {
      void supabase.removeChannel(channel);
    };
  }, [enabled, loadGameState, resolvedGameId]);

  const players = gameState?.players ?? [];
  const currentPlayer = useMemo(
    () => players.find((player) => player.userId === currentPlayerId) ?? null,
    [currentPlayerId, players],
  );
  const currentTurnPlayer = useMemo(
    () =>
      players.find((player) => player.id === gameState?.currentTurnPlayerId) ??
      null,
    [gameState?.currentTurnPlayerId, players],
  );
  const applyStateSnapshot = useCallback((snapshot: unknown) => {
    const nextState = readGameState(snapshot);

    if (!nextState) {
      return;
    }

    requestIdRef.current += 1;

    setGameState((currentState) =>
      mergeFreshGameState(currentState, {
        ...nextState,
        log:
          currentState?.gameId === nextState.gameId
            ? currentState.log
            : nextState.log,
      }),
    );
    setLastSyncedAt(new Date().toISOString());
    setResolvedGameId(nextState.gameId);
  }, []);
  const refresh = useCallback(
    () => loadGameState({ silent: true }),
    [loadGameState],
  );

  return {
    applyStateSnapshot,
    currentPlayer,
    currentPlayerId,
    currentTurnPlayer,
    error,
    gameState,
    isBrowserOnline,
    isRealtimeConnected: realtimeStatus === 'subscribed',
    lastSyncedAt,
    loading,
    players,
    realtimeStatus,
    refresh,
    refreshing,
  };
}
