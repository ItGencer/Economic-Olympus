// app/opengraph-image.tsx
import { ImageResponse } from 'next/og';

export const size = { width: 1200, height: 630 };
export const contentType = 'image/png';

export default function Image() {
  return new ImageResponse(
    (
      <div
        style={{
          width: '100%',
          height: '100%',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          background: 'linear-gradient(135deg, #1a0b2e, #7c3aed)',
          color: 'white',
          fontSize: 80,
          fontWeight: 700,
        }}
      >
        Economic Olympus
      </div>
    ),
    { ...size }
  );
}