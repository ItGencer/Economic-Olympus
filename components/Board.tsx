import boardConfig from '@/board-config.json';
import type { Cell, CellId, CellType, PlayerId, Ring } from '@/types';
import type { ReactNode } from 'react';

type BoardPlayer = {
  id: PlayerId;
  name: string;
  cellId: CellId;
  color?: string;
};

type BoardProps = {
  activeCellId?: CellId;
  cells?: Cell[];
  centerSlot?: ReactNode;
  className?: string;
  players?: BoardPlayer[];
};

type CellPosition = {
  col: number;
  row: number;
};

const configuredCells = boardConfig as Cell[];

const typeStyles: Record<CellType, string> = {
  advertising: 'border-amber-300 bg-amber-50 text-amber-950',
  casino: 'border-fuchsia-300 bg-fuchsia-50 text-fuchsia-950',
  client: 'border-cyan-300 bg-cyan-50 text-cyan-950',
  company: 'border-indigo-300 bg-indigo-50 text-indigo-950',
  deal: 'border-emerald-300 bg-emerald-50 text-emerald-950',
  director: 'border-slate-400 bg-slate-100 text-slate-950',
  image: 'border-sky-300 bg-sky-50 text-sky-950',
  negative_reputation: 'border-rose-300 bg-rose-50 text-rose-950',
  positive_reputation: 'border-lime-300 bg-lime-50 text-lime-950',
  random: 'border-violet-300 bg-violet-50 text-violet-950',
  salary: 'border-green-300 bg-green-50 text-green-950',
  start: 'border-slate-950 bg-white text-slate-950',
  tax: 'border-orange-300 bg-orange-50 text-orange-950',
  tender: 'border-teal-300 bg-teal-50 text-teal-950',
  vacation: 'border-blue-300 bg-blue-50 text-blue-950',
};

const defaultPlayerColors = [
  '#059669',
  '#2563eb',
  '#dc2626',
  '#9333ea',
  '#d97706',
  '#0f766e',
];

function joinClassNames(...classes: Array<string | false | undefined>) {
  return classes.filter(Boolean).join(' ');
}

function getRingSideLength(cellCount: number) {
  return Math.max(2, Math.ceil(cellCount / 4) + 1);
}

function getPerimeterPositions(sideLength: number, offset: number): CellPosition[] {
  const last = offset + sideLength - 1;
  const positions: CellPosition[] = [];

  for (let col = offset; col <= last; col += 1) {
    positions.push({ col, row: offset });
  }

  for (let row = offset + 1; row <= last - 1; row += 1) {
    positions.push({ col: last, row });
  }

  for (let col = last; col >= offset; col -= 1) {
    positions.push({ col, row: last });
  }

  for (let row = last - 1; row >= offset + 1; row -= 1) {
    positions.push({ col: offset, row });
  }

  return positions;
}

function getCellsByRing(cells: Cell[], ring: Ring) {
  return cells.filter((cell) => cell.ring === ring);
}

function getPlayersByCell(players: BoardPlayer[]) {
  return players.reduce<Record<CellId, BoardPlayer[]>>((accumulator, player) => {
    accumulator[player.cellId] ??= [];
    accumulator[player.cellId].push(player);
    return accumulator;
  }, {});
}

function CellTile({
  cell,
  isActive,
  players,
  position,
}: {
  cell: Cell;
  isActive: boolean;
  players: BoardPlayer[];
  position: CellPosition;
}) {
  return (
    <div
      className={joinClassNames(
        'relative flex min-h-0 min-w-0 flex-col justify-between rounded-md border p-1 shadow-sm transition',
        'focus-within:ring-2 focus-within:ring-emerald-500',
        typeStyles[cell.type],
        isActive && 'ring-2 ring-emerald-600 ring-offset-2 ring-offset-slate-50',
      )}
      style={{
        gridColumn: position.col,
        gridRow: position.row,
      }}
      title={`${cell.params.label} (${cell.type})`}
    >
      <span className="block overflow-hidden text-center text-[9px] font-bold leading-tight [overflow-wrap:anywhere] sm:text-[10px]">
        {cell.params.label}
      </span>

      {players.length > 0 ? (
        <div className="mt-1 flex min-h-3 justify-center gap-0.5">
          {players.slice(0, 4).map((player, index) => (
            <span
              aria-label={player.name}
              className="h-2.5 w-2.5 rounded-full border border-white shadow-sm"
              key={player.id}
              style={{
                backgroundColor:
                  player.color ?? defaultPlayerColors[index % defaultPlayerColors.length],
              }}
              title={player.name}
            />
          ))}
          {players.length > 4 ? (
            <span className="text-[9px] font-bold leading-none text-slate-700">
              +{players.length - 4}
            </span>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}

export function Board({
  activeCellId,
  cells = configuredCells,
  centerSlot,
  className,
  players = [],
}: BoardProps) {
  const outerCells = getCellsByRing(cells, 'outer');
  const innerCells = getCellsByRing(cells, 'inner');
  const outerSideLength = getRingSideLength(outerCells.length);
  const innerSideLength = getRingSideLength(innerCells.length);
  const gridSideLength = Math.max(outerSideLength, innerSideLength + 4);
  const outerOffset = Math.floor((gridSideLength - outerSideLength) / 2) + 1;
  const innerOffset = Math.floor((gridSideLength - innerSideLength) / 2) + 1;
  const outerPositions = getPerimeterPositions(outerSideLength, outerOffset);
  const innerPositions = getPerimeterPositions(innerSideLength, innerOffset);
  const centerStart = innerOffset + 1;
  const centerEnd = innerOffset + innerSideLength - 1;
  const playersByCell = getPlayersByCell(players);

  return (
    <section
      aria-label="Ігрова дошка"
      className={joinClassNames('w-full max-w-5xl', className)}
    >
      <div
        className="grid aspect-square w-full gap-1 rounded-md border border-slate-200 bg-slate-100 p-2 shadow-sm sm:gap-1.5 sm:p-3"
        style={{
          gridTemplateColumns: `repeat(${gridSideLength}, minmax(0, 1fr))`,
          gridTemplateRows: `repeat(${gridSideLength}, minmax(0, 1fr))`,
        }}
      >
        {outerCells.map((cell, index) => (
          <CellTile
            cell={cell}
            isActive={cell.id === activeCellId}
            key={cell.id}
            players={playersByCell[cell.id] ?? []}
            position={outerPositions[index]}
          />
        ))}

        {innerCells.map((cell, index) => (
          <CellTile
            cell={cell}
            isActive={cell.id === activeCellId}
            key={cell.id}
            players={playersByCell[cell.id] ?? []}
            position={innerPositions[index]}
          />
        ))}

        <div
          className="flex min-h-0 min-w-0 items-center justify-center rounded-md border border-dashed border-slate-300 bg-white p-3 text-center"
          style={{
            gridColumn: `${centerStart} / ${centerEnd}`,
            gridRow: `${centerStart} / ${centerEnd}`,
          }}
        >
          {centerSlot ?? (
            <div>
              <p className="text-xs font-semibold uppercase tracking-normal text-slate-500">
                Центр поля
              </p>
              <p className="mt-1 text-sm font-bold text-slate-950">
                Кубик з'явиться тут
              </p>
            </div>
          )}
        </div>
      </div>
    </section>
  );
}

export default Board;
