import type { Metadata } from 'next';

import { AuthProvider } from '@/components/AuthProvider';
import { LanguageProvider } from '@/components/LanguageProvider';
import SiteFooter from '@/components/SiteFooter';

import './globals.css';

export const metadata: Metadata = {
  metadataBase: new URL('https://economic-olympus.vercel.app'),
  title: 'Economic Olympus',
  description:
    'Economic Olympus — онлайн стратегічна настільна гра про репутацію, ризик і контроль активів.',
  icons: {
    icon: '/favicon.ico',
    shortcut: '/favicon.ico',
  },
  openGraph: {
    title: 'Economic Olympus',
    description:
      'Онлайн стратегічна настільна гра про репутацію, ризик і контроль активів.',
    url: 'https://economic-olympus.vercel.app/',
    siteName: 'Economic Olympus',
    images: [
      {
        url: '/og-image.png',
        width: 1200,
        height: 630,
        alt: 'Economic Olympus',
      },
    ],
    locale: 'uk_UA',
    type: 'website',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Economic Olympus',
    description:
      'Онлайн стратегічна настільна гра про репутацію, ризик і контроль активів.',
    images: ['/og-image.png'],
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