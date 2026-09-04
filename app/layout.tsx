import type { Metadata } from 'next';

import { AuthProvider } from '@/components/AuthProvider';
import FullscreenToggle from '@/components/FullscreenToggle';
import { LanguageProvider } from '@/components/LanguageProvider';
import SiteFooter from '@/components/SiteFooter';

import './globals.css';

const appName = 'Economic Olympus';
const appUrl = 'https://economic-olympus.vercel.app';
const appDescription =
  'Economic Olympus — онлайн стратегічна настільна гра про репутацію, ризик і контроль активів.';

export const metadata: Metadata = {
  metadataBase: new URL(appUrl),
  title: {
    default: appName,
    template: `%s | ${appName}`,
  },
  description: appDescription,
  applicationName: appName,
  alternates: {
    canonical: '/',
  },
  icons: {
    icon: '/favicon.ico',
    shortcut: '/favicon.ico',
  },
  openGraph: {
    title: appName,
    description: appDescription,
    url: appUrl,
    siteName: appName,
    images: [
      {
        url: '/og-image.png',
        width: 1200,
        height: 630,
        alt: appName,
      },
    ],
    locale: 'uk_UA',
    type: 'website',
  },
  twitter: {
    card: 'summary_large_image',
    title: appName,
    description: appDescription,
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
            <FullscreenToggle />
            {children}
            <SiteFooter />
          </AuthProvider>
        </LanguageProvider>
      </body>
    </html>
  );
}
