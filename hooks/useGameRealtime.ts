'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { ensureAnonymousSession, getSupabaseClient } from '@/lib/supabase';
import type { GameId, GameState, GameStatus, Player, PlayerId } from '@/types';

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
  isRealtimeConnected: boolean;
  loading: boolean;
  players: Player[];
  realtimeStatus: GameRealtimeStatus;
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

function readGameState(value: unknown): GameState | null {
  if (!isRecord(value)) {
    return null;
  }

  const players = Array.isArray(value.players) ? (value.players as Player[]) : [];

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

  return {
    ...state,
    currentTurnPlayerId: row.current_turn_player_id,
    gameId: row.id,
    joinCode: row.join_code,
    maxPlayers: row.max_players,
    status: row.status,
    updatedAt: row.updated_at,
    winnerPlayerId: row.winner_player_id,
  };
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

      if (silent) {
        setRefreshing(true);
      } else {
        setLoading(true);
      }

      setError(null);

      try {
        const user = await ensureAnonymousSession();
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
          setResolvedGameId(null);
          return;
        }

        const nextState = readStateFromRow(data as GameRow);

        setGameState(nextState);
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
    if (!enabled || !resolvedGameId) {
      setRealtimeStatus('idle');
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

          setGameState(nextState);
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
      .subscribe((status) => {
        setRealtimeStatus(toRealtimeStatus(status));
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
  const refresh = useCallback(
    () => loadGameState({ silent: true }),
    [loadGameState],
  );

  return {
    currentPlayer,
    currentPlayerId,
    currentTurnPlayer,
    error,
    gameState,
    isRealtimeConnected: realtimeStatus === 'subscribed',
    loading,
    players,
    realtimeStatus,
    refresh,
    refreshing,
  };
}
