import { createAvatar } from '@dicebear/core';
import * as adventurer from '@dicebear/adventurer';
import * as bottts from '@dicebear/bottts';
import * as identicon from '@dicebear/identicon';
import * as pixelArt from '@dicebear/pixel-art';
import * as shapes from '@dicebear/shapes';
import * as thumbs from '@dicebear/thumbs';

import {
  normalizeAvatarColor,
  normalizeAvatarStyle,
  toDiceBearBackgroundColor,
  type PlayerAvatarStyle,
} from '@/lib/playerAvatarConfig';

type AvatarOptions = {
  backgroundColor: string[];
  radius: number;
  scale: number;
  seed: string;
  size: number;
};

const avatarScaleByStyle: Record<PlayerAvatarStyle, number> = {
  adventurer: 112,
  bottts: 116,
  identicon: 108,
  'pixel-art': 118,
  shapes: 102,
  thumbs: 104,
};

function createAvatarSvgForStyle(
  style: PlayerAvatarStyle,
  options: AvatarOptions,
) {
  switch (style) {
    case 'bottts':
      return createAvatar(bottts, options).toString();
    case 'identicon':
      return createAvatar(identicon, options).toString();
    case 'pixel-art':
      return createAvatar(pixelArt, options).toString();
    case 'shapes':
      return createAvatar(shapes, options).toString();
    case 'thumbs':
      return createAvatar(thumbs, options).toString();
    case 'adventurer':
    default:
      return createAvatar(adventurer, options).toString();
  }
}

export class PlayerAvatarService {
  static generateAvatarSvg(
    style: string,
    seed: string,
    backgroundColor: string,
  ): string {
    const avatarStyle = normalizeAvatarStyle(style);
    const avatarSeed = seed.trim() || 'Economic Olympus';
    const avatarColor = normalizeAvatarColor(backgroundColor);
    return createAvatarSvgForStyle(avatarStyle, {
      backgroundColor: [toDiceBearBackgroundColor(avatarColor)],
      radius: 50,
      scale: avatarScaleByStyle[avatarStyle],
      seed: `${avatarSeed}-${avatarStyle}`,
      size: 96,
    });
  }
}

export function generateAvatarSvg(
  style: string,
  seed: string,
  backgroundColor: string,
) {
  return PlayerAvatarService.generateAvatarSvg(style, seed, backgroundColor);
}

export type { PlayerAvatarStyle };
