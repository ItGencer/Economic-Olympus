import type { Metadata } from 'next';

import { AuthProvider } from '@/components/AuthProvider';

import './globals.css';

export const metadata: Metadata = {
  title: 'Економічна Монополія',
  description:
    'Онлайн економічна настільна гра з серверною логікою через Supabase.',
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="uk">
      <body>
        <AuthProvider>{children}</AuthProvider>
      </body>
    </html>
  );
}
