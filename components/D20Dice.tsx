'use client';

import Image from 'next/image';

type D20DiceProps = {
  className?: string;
  rolling?: boolean;
  value?: number | null;
};

function joinClassNames(...classes: Array<string | false | null | undefined>) {
  return classes.filter(Boolean).join(' ');
}

export function D20Dice({ className, rolling = false, value = null }: D20DiceProps) {
  return (
    <div
      aria-label="Кубик d20"
      className={joinClassNames(
        'relative mx-auto aspect-square w-28 overflow-hidden rounded-full bg-white/95 shadow-2xl shadow-rose-950/30 ring-4 ring-white/60',
        className,
      )}
    >
      <Image
        alt=""
        aria-hidden="true"
        className={joinClassNames(
          'object-cover transition-transform duration-500',
          rolling && 'animate-spin',
        )}
        fill
        sizes="112px"
        src="/deal-cards/d20.jpg"
      />
      <div className="absolute inset-0 flex items-center justify-center bg-rose-950/10">
        <span className="rounded-full bg-white/90 px-3 py-1 text-2xl font-black text-rose-700 shadow-lg">
          {rolling ? '...' : value ?? '?'}
        </span>
      </div>
    </div>
  );
}

export default D20Dice;
