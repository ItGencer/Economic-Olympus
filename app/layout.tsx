import type { Metadata } from 'next';

import { AuthProvider } from '@/components/AuthProvider';
import { LanguageProvider } from '@/components/LanguageProvider';
import SiteFooter from '@/components/SiteFooter';

import './globals.css';

export const metadata: Metadata = {
  title: 'Economic Olympus',
  description:
    'Онлайн економічна настільна гра з авторизацією, лобі та серверною логікою через Supabase.',
  icons: {
    icon: '/favicon.ico',
    shortcut: '/favicon.ico',
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="uk">
      <body className="neo-theme">
        <LanguageProvider>
          <AuthProvider>
            {children}
            <SiteFooter />
          </AuthProvider>
        </LanguageProvider>
      </body>
    </html>
  );
}
