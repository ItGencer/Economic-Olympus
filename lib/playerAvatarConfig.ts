export const avatarStyleOptions = [
  { id: 'adventurer', label: 'Adventurer' },
  { id: 'bottts', label: 'Bottts' },
  { id: 'pixel-art', label: 'Pixel Art' },
  { id: 'identicon', label: 'Identicon' },
  { id: 'thumbs', label: 'Thumbs' },
  { id: 'shapes', label: 'Shapes' },
] as const;

export type PlayerAvatarStyle = (typeof avatarStyleOptions)[number]['id'];

export const avatarColorOptions = [
  '#7c3aed',
  '#a855f7',
  '#c084fc',
  '#ec4899',
  '#06b6d4',
  '#10b981',
  '#f59e0b',
  '#ef4444',
] as const;

export const defaultAvatarStyle: PlayerAvatarStyle = 'adventurer';
export const defaultAvatarColor = '#7c3aed';

const supportedAvatarStyles = new Set<string>(
  avatarStyleOptions.map((option) => option.id),
);

export function isSupportedAvatarStyle(
  value: string | null | undefined,
): value is PlayerAvatarStyle {
  return Boolean(value && supportedAvatarStyles.has(value));
}

export function normalizeAvatarStyle(
  value: string | null | undefined,
): PlayerAvatarStyle {
  return isSupportedAvatarStyle(value) ? value : defaultAvatarStyle;
}

export function normalizeAvatarColor(value: string | null | undefined) {
  if (typeof value === 'string' && /^#[0-9a-fA-F]{6}$/.test(value)) {
    return value.toLowerCase();
  }

  return defaultAvatarColor;
}

export function toDiceBearBackgroundColor(value: string) {
  return normalizeAvatarColor(value).replace('#', '');
}
