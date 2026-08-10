import boardConfig from '@/board-config.json';
import PlayerAvatarToken from '@/components/PlayerAvatarToken';
import type { Cell, CellId, CellType, PlayerId, Ring } from '@/types';
import type { ReactNode } from 'react';

type BoardPlayer = {
  avatarColor?: string;
  avatarStyle?: string;
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
  advertising: 'border-amber-300/70 bg-amber-300/10 text-amber-100',
  casino: 'border-fuchsia-300/75 bg-fuchsia-400/12 text-fuchsia-100',
  client: 'border-cyan-300/75 bg-cyan-400/10 text-cyan-100',
  company: 'border-indigo-300/75 bg-indigo-400/12 text-indigo-100',
  deal: 'border-emerald-300/75 bg-emerald-400/10 text-emerald-100',
  director: 'border-slate-300/70 bg-slate-300/10 text-slate-100',
  image: 'border-sky-300/75 bg-sky-400/10 text-sky-100',
  negative_reputation: 'border-rose-300/75 bg-rose-400/12 text-rose-100',
  positive_reputation: 'border-lime-300/75 bg-lime-400/10 text-lime-100',
  random: 'border-violet-300/80 bg-violet-400/14 text-violet-100',
  salary: 'border-green-300/75 bg-green-400/10 text-green-100',
  start: 'border-violet-100/80 bg-white/8 text-slate-100',
  tax: 'border-orange-300/75 bg-orange-400/10 text-orange-100',
  tender: 'border-teal-300/75 bg-teal-400/10 text-teal-100',
  vacation: 'border-blue-300/75 bg-blue-400/10 text-blue-100',
};

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
        'neo-cell relative flex min-h-0 min-w-0 flex-col justify-between rounded-md border p-1.5 shadow-sm transition duration-300',
        'focus-within:ring-2 focus-within:ring-violet-400',
        typeStyles[cell.type],
        isActive && 'ring-2 ring-violet-300 ring-offset-2 ring-offset-[#12121a]',
      )}
      style={{
        gridColumn: position.col,
        gridRow: position.row,
      }}
      title={`${cell.params.label} (${cell.type})`}
    >
      <span className="block overflow-hidden text-center text-[10px] font-bold leading-tight [overflow-wrap:anywhere] md:text-[11px]">
        {cell.params.label}
      </span>

      {players.length > 0 ? (
        <div className="mt-1 flex min-h-10 justify-center -space-x-2">
          {players.slice(0, 4).map((player) => (
            <PlayerAvatarToken
              avatarColor={player.avatarColor}
              avatarStyle={player.avatarStyle}
              className="relative ring-2 ring-[#151522]"
              key={player.id}
              name={player.name}
              size="sm"
            />
          ))}
          {players.length > 4 ? (
            <span className="grid h-10 w-10 place-items-center rounded-full border border-violet-300/40 bg-[#181824] text-[10px] font-bold leading-none text-fuchsia-100 shadow-[0_0_14px_rgba(192,132,252,0.35)]">
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
      className={joinClassNames(
        'neo-board-scroll w-full max-w-5xl overflow-auto overscroll-contain pb-2 max-h-[calc(100vh-7rem)] xl:sticky xl:top-4 xl:max-h-[calc(100vh-2rem)]',
        className,
      )}
    >
      <div
        className="neo-panel neo-grid-glow grid aspect-square w-full gap-1.5 rounded-[20px] border border-violet-300/25 bg-[#151522] p-2 shadow-sm max-[768px]:min-w-[760px] sm:p-3"
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
          className="neo-panel-pressed flex min-h-0 min-w-0 items-center justify-center overflow-hidden rounded-[18px] border border-dashed border-violet-300/30 bg-[#12121a]/80 p-2 text-center lg:p-3"
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
