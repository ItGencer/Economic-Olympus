'use client';

import { useId, useMemo } from 'react';

import { PlayerAvatarService } from '@/lib/PlayerAvatarService';
import {
  defaultAvatarColor,
  defaultAvatarStyle,
  normalizeAvatarColor,
  normalizeAvatarStyle,
  type PlayerAvatarStyle,
} from '@/lib/playerAvatarConfig';

type PlayerAvatarTokenProps = {
  avatarColor?: string;
  avatarStyle?: string;
  className?: string;
  name: string;
  size?: 'sm' | 'md' | 'lg';
};

const sizeClasses = {
  lg: 'h-16 w-16',
  md: 'h-12 w-12',
  sm: 'h-10 w-10',
};

const styleMarks: Record<PlayerAvatarStyle, string> = {
  adventurer: 'AD',
  bottts: 'BT',
  identicon: 'ID',
  'pixel-art': 'PX',
  shapes: 'SH',
  thumbs: 'TH',
};

const markClasses = {
  lg: 'h-5 min-w-5 px-1 text-[8px]',
  md: 'h-4 min-w-4 px-1 text-[7px]',
  sm: 'h-3.5 min-w-3.5 px-0.5 text-[6px]',
};

function joinClassNames(...classes: Array<string | false | undefined>) {
  return classes.filter(Boolean).join(' ');
}

export function PlayerAvatarToken({
  avatarColor = defaultAvatarColor,
  avatarStyle = defaultAvatarStyle,
  className,
  name,
  size = 'md',
}: PlayerAvatarTokenProps) {
  const idScope = useId();
  const safeAvatarStyle = normalizeAvatarStyle(avatarStyle);
  const safeAvatarColor = normalizeAvatarColor(avatarColor);
  const svg = useMemo(
    () =>
      PlayerAvatarService.generateAvatarSvg(
        safeAvatarStyle,
        name,
        safeAvatarColor,
        idScope,
      ),
    [idScope, safeAvatarColor, safeAvatarStyle, name],
  );

  return (
    <span
      aria-label={`Фішка гравця ${name}`}
      className={joinClassNames(
        'relative inline-flex shrink-0 overflow-hidden rounded-full border border-violet-200/80 p-0.5 shadow-[0_0_20px_rgba(192,132,252,0.52),inset_0_0_12px_rgba(255,255,255,0.16)] ring-1 ring-violet-400/35',
        sizeClasses[size],
        className,
      )}
      data-i18n-ignore="true"
      role="img"
      style={{
        background: `radial-gradient(circle at 30% 22%, rgba(255,255,255,0.38), transparent 26%), linear-gradient(135deg, ${safeAvatarColor}, #181824 82%)`,
      }}
      title={name}
    >
      <span
        className="pointer-events-none absolute inset-[3px] rounded-full bg-[#12121a]/24 shadow-[inset_0_0_18px_rgba(2,2,8,0.28)]"
        aria-hidden="true"
      />
      <span
        className="relative z-10 block h-full w-full overflow-hidden rounded-full [&>svg]:block [&>svg]:h-full [&>svg]:w-full [&>svg]:rounded-full"
        dangerouslySetInnerHTML={{ __html: svg }}
      />
      <span
        aria-hidden="true"
        className={joinClassNames(
          'absolute bottom-0 right-0 z-20 grid place-items-center rounded-full border border-fuchsia-100/70 bg-[#12121a]/92 font-black leading-none text-fuchsia-50 shadow-[0_0_10px_rgba(192,132,252,0.65)]',
          markClasses[size],
        )}
      >
        {styleMarks[safeAvatarStyle]}
      </span>
    </span>
  );
}

export default PlayerAvatarToken;
