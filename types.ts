export type GameStatus = 'lobby' | 'in_progress' | 'finished';

export type Ring = 'inner' | 'outer';

export type CellType =
  | 'start'
  | 'casino'
  | 'random'
  | 'vacation'
  | 'deal'
  | 'image'
  | 'negative_reputation'
  | 'salary'
  | 'tax'
  | 'advertising'
  | 'positive_reputation'
  | 'client'
  | 'tender'
  | 'company'
  | 'director';

export type PlayerId = string;
export type GameId = string;
export type CellId = string;
export type CompanyId = string;
export type TenderId = string;
export type DirectorId = string;

export type RandomSign = 'positive' | 'negative';
export type CasinoChoice = 'even' | 'odd';
export type Decision = 'accept' | 'decline';
export type DirectorStatus = 'candidate' | 'active' | 'former';

export interface BaseCellParams {
  label: string;
}

export interface StartCellParams extends BaseCellParams {}

export interface CasinoCellParams extends BaseCellParams {}

export interface RandomCellParams extends BaseCellParams {
  amountStep?: number;
  maxAmount?: number;
  minAmount?: number;
  negativeMax?: number;
  negativeMin?: number;
  positiveMax?: number;
  positiveMin?: number;
  sign?: RandomSign;
}

export interface VacationCellParams extends BaseCellParams {
  skipTurns: number;
}

export interface DealCellParams extends BaseCellParams {
  coefficientMin: number;
  coefficientMax: number;
  unitValue: number;
  incomeMin?: number;
  incomeMax?: number;
  importanceMin?: number;
  importanceMax?: number;
}

export interface ImageCellParams extends BaseCellParams {
  priceMin: number;
  priceMax: number;
  imageMin: number;
  imageMax: number;
  entry?: boolean;
  corner?: 'top_left' | 'top_right' | 'bottom_right' | 'bottom_left';
}

export interface ReputationCellParams extends BaseCellParams {
  dieMax?: number;
  dieMin?: number;
  imageDelta?: number;
  multiplierMax?: number;
  multiplierMin?: number;
}

export interface SalaryCellParams extends BaseCellParams {
  imageMultiplier: number;
}

export interface TaxCellParams extends BaseCellParams {
  rate: number;
}

export interface AdvertisingCellParams extends BaseCellParams {
  priceMin: number;
  priceMax: number;
  imageMin: number;
  imageMax: number;
}

export interface ClientCellParams extends BaseCellParams {
  relationshipMin: number;
  relationshipMax: number;
  percentStep: number;
}

export interface TenderCellParams extends BaseCellParams {
  tenderId: TenderId;
  country: string;
  buyout: number;
  price: number;
}

export interface CompanyCellParams extends BaseCellParams {
  companyId: CompanyId;
  name: string;
  totalShares: number;
  sharePrice: number;
  inventoryPerShare: number;
}

export interface DirectorCellParams extends BaseCellParams {
  minOwnershipPercent: number;
  votingCoefficient: number;
  voteDifficulty: number;
}

export type CellParams =
  | StartCellParams
  | CasinoCellParams
  | RandomCellParams
  | VacationCellParams
  | DealCellParams
  | ImageCellParams
  | ReputationCellParams
  | SalaryCellParams
  | TaxCellParams
  | AdvertisingCellParams
  | ClientCellParams
  | TenderCellParams
  | CompanyCellParams
  | DirectorCellParams;

export interface Cell<TParams extends CellParams = CellParams> {
  id: CellId;
  ring: Ring;
  type: CellType;
  params: TParams;
}

export interface Deal {
  id: string;
  gameId: GameId;
  playerId: PlayerId;
  income: number;
  importance: number;
  decision?: Decision;
  dice?: [number, number];
  modifiedResult?: number;
  successful?: boolean;
  resolvedAt?: string;
}

export interface Tender {
  id: TenderId;
  gameId: GameId;
  country: string;
  buyout: number;
  price: number;
  ownerPlayerId: PlayerId | null;
}

export interface Company {
  id: CompanyId;
  gameId: GameId;
  name: string;
  totalShares: number;
  sharePrice: number;
  inventoryPerShare: number;
  shareholders: Record<PlayerId, number>;
}

export interface Director {
  id: DirectorId;
  gameId: GameId;
  companyId: CompanyId;
  playerId: PlayerId;
  status: DirectorStatus;
  votingCoefficient: number;
  voteDifficulty: number;
  electedAt?: string;
}

export interface Player {
  id: PlayerId;
  gameId: GameId;
  userId: string | null;
  seatNumber: number;
  name: string;
  isBot: boolean;
  avatarStyle: string;
  avatarColor: string;
  ring: Ring;
  cellId: CellId;
  balance: number;
  image: number;
  inventory: number;
  successfulDeals: number;
  failedDeals: number;
  debtLocked: boolean;
  debtWarning?: boolean;
  eliminated?: boolean;
  skipTurns: number;
  shares: Record<CompanyId, number>;
  tenderIds: TenderId[];
  directorIds: DirectorId[];
  createdAt: string;
  updatedAt: string;
}

export type TurnPhase =
  | 'awaiting_roll'
  | 'moving'
  | 'awaiting_decision'
  | 'resolving_cell'
  | 'finished';

export interface Turn {
  id: string;
  gameId: GameId;
  number: number;
  playerId: PlayerId;
  phase: TurnPhase;
  dice?: number[];
  fromCellId?: CellId;
  toCellId?: CellId;
  pendingActionId?: string;
  startedAt: string;
  finishedAt?: string;
}

export type PendingActionType =
  | 'deal_decision'
  | 'casino_bet'
  | 'image_offer'
  | 'random_event'
  | 'advertising_offer'
  | 'client_decision'
  | 'client_stock_choice'
  | 'tender_purchase'
  | 'company_share_purchase'
  | 'negative_reputation'
  | 'salary'
  | 'outer_ring_choice'
  | 'ceo_election';

export interface PendingAction {
  id: string;
  type: PendingActionType;
  playerId: PlayerId;
  cellId?: CellId;
  payload: Record<string, unknown>;
  createdAt: string;
}

export interface GameLogEntry {
  id: string;
  gameId: GameId;
  turnNumber?: number;
  playerId?: PlayerId;
  eventType: string;
  message: string;
  payload: Record<string, unknown>;
  createdAt: string;
}

export interface GameState {
  gameId: GameId;
  status: GameStatus;
  joinCode: string;
  maxPlayers: number;
  currentTurnPlayerId: PlayerId | null;
  winnerPlayerId: PlayerId | null;
  players: Player[];
  turn: Turn | null;
  pendingAction: PendingAction | null;
  companies: Record<CompanyId, Company>;
  tenders: Record<TenderId, Tender>;
  directors: Record<DirectorId, Director>;
  log: GameLogEntry[];
  createdAt: string;
  updatedAt: string;
}
