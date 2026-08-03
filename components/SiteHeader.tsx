'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useEffect, useMemo, useState } from 'react';

import AuthButton from '@/components/AuthButton';
import { useAuth } from '@/components/AuthProvider';

type HeaderLink = {
  href: string;
  label: string;
};

type SiteHeaderProps = {
  extraLinks?: HeaderLink[];
  maxWidth?: 'default' | 'wide';
  startHref?: string;
};

const DEFAULT_EXTRA_LINKS: HeaderLink[] = [];

function readUserName(user: ReturnType<typeof useAuth>['user']) {
  if (!user) {
    return '';
  }

  const metadata = user.user_metadata;
  const name = metadata.full_name ?? metadata.name ?? user.email;

  return typeof name === 'string' && name.trim() ? name : 'Користувач';
}

function readAvatarUrl(user: ReturnType<typeof useAuth>['user']) {
  if (!user) {
    return null;
  }

  const avatarUrl = user.user_metadata.avatar_url ?? user.user_metadata.picture;

  return typeof avatarUrl === 'string' && avatarUrl.trim() ? avatarUrl : null;
}

function readPathFromHref(href: string) {
  return href.split('#')[0] || null;
}

function isActiveLink(pathname: string, href: string) {
  const hrefPath = readPathFromHref(href);

  if (!hrefPath) {
    return false;
  }

  if (hrefPath === '/') {
    return pathname === '/';
  }

  return pathname === hrefPath || pathname.startsWith(`${hrefPath}/`);
}

export function SiteHeader({
  extraLinks = DEFAULT_EXTRA_LINKS,
  maxWidth = 'default',
  startHref = '/#start',
}: SiteHeaderProps) {
  const pathname = usePathname();
  const { loading, openAuthModal, signOut, user } = useAuth();
  const [menuOpen, setMenuOpen] = useState(false);
  const userName = readUserName(user);
  const avatarUrl = readAvatarUrl(user);
  const initial = userName.trim().charAt(0).toUpperCase() || 'U';
  const containerClass =
    maxWidth === 'wide' ? 'max-w-[1600px]' : 'max-w-7xl';
  const links = useMemo(
    () => [
      { href: '/', label: 'Головна' },
      { href: '/rules', label: 'Правила гри' },
      { href: startHref, label: 'Почати гру' },
      ...extraLinks,
    ],
    [extraLinks, startHref],
  );

  useEffect(() => {
    setMenuOpen(false);
  }, [pathname]);

  function handleOpenAuth() {
    setMenuOpen(false);
    openAuthModal();
  }

  function handleSignOut() {
    setMenuOpen(false);
    void signOut();
  }

  return (
    <header className="sticky top-0 z-40 border-b border-slate-200 bg-white/95 shadow-sm backdrop-blur">
      <div
        className={`mx-auto flex w-full ${containerClass} items-center justify-between gap-3 px-4 py-3 sm:px-6`}
      >
        <Link
          className="min-w-0 text-base font-bold tracking-normal text-slate-950 sm:text-lg"
          href="/"
        >
          Economic Olympus
        </Link>

        <nav className="hidden items-center gap-6 text-sm font-semibold text-slate-600 min-[769px]:flex">
          {links.map((link) => {
            const active = isActiveLink(pathname, link.href);

            return (
              <Link
                className={
                  active
                    ? 'text-slate-950'
                    : 'transition hover:text-slate-950'
                }
                href={link.href}
                key={`${link.href}-${link.label}`}
              >
                {link.label}
              </Link>
            );
          })}
        </nav>

        <div className="hidden min-[769px]:block">
          <AuthButton />
        </div>

        <button
          aria-controls="site-mobile-menu"
          aria-expanded={menuOpen}
          aria-label={menuOpen ? 'Закрити меню' : 'Відкрити меню'}
          className="inline-grid h-10 w-10 place-items-center rounded-md border border-slate-300 bg-white text-slate-800 shadow-sm transition hover:border-slate-400 hover:bg-slate-50 min-[769px]:hidden"
          onClick={() => setMenuOpen((open) => !open)}
          type="button"
        >
          <span className="grid gap-1.5">
            <span
              className={`block h-0.5 w-5 rounded-full bg-current transition ${
                menuOpen ? 'translate-y-2 rotate-45' : ''
              }`}
            />
            <span
              className={`block h-0.5 w-5 rounded-full bg-current transition ${
                menuOpen ? 'opacity-0' : ''
              }`}
            />
            <span
              className={`block h-0.5 w-5 rounded-full bg-current transition ${
                menuOpen ? '-translate-y-2 -rotate-45' : ''
              }`}
            />
          </span>
        </button>
      </div>

      {menuOpen ? (
        <div
          className="border-t border-slate-200 bg-white shadow-lg min-[769px]:hidden"
          id="site-mobile-menu"
        >
          <div className={`mx-auto w-full ${containerClass} px-4 py-4 sm:px-6`}>
            <nav className="grid gap-2">
              {links.map((link) => {
                const active = isActiveLink(pathname, link.href);

                return (
                  <Link
                    className={`rounded-md px-3 py-3 text-sm font-bold transition ${
                      active
                        ? 'bg-slate-950 text-white'
                        : 'text-slate-700 hover:bg-slate-100 hover:text-slate-950'
                    }`}
                    href={link.href}
                    key={`${link.href}-${link.label}-mobile`}
                    onClick={() => setMenuOpen(false)}
                  >
                    {link.label}
                  </Link>
                );
              })}
            </nav>

            <div className="mt-4 border-t border-slate-200 pt-4">
              {loading ? (
                <div className="h-11 rounded-md border border-slate-200 bg-slate-50" />
              ) : user ? (
                <div className="grid gap-3">
                  <div className="flex min-w-0 items-center gap-3 rounded-md bg-slate-50 p-3">
                    <span
                      aria-hidden="true"
                      className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-slate-900 bg-cover bg-center text-sm font-bold text-white"
                      style={
                        avatarUrl
                          ? { backgroundImage: `url(${avatarUrl})` }
                          : undefined
                      }
                    >
                      {avatarUrl ? null : initial}
                    </span>
                    <div className="min-w-0">
                      <p className="truncate text-sm font-bold text-slate-950">
                        {userName}
                      </p>
                      {user.email ? (
                        <p className="truncate text-xs font-semibold text-slate-500">
                          {user.email}
                        </p>
                      ) : null}
                    </div>
                  </div>

                  <Link
                    className="inline-flex h-11 items-center justify-center rounded-md border border-slate-300 px-4 text-sm font-bold text-slate-700 transition hover:border-slate-400 hover:bg-slate-100"
                    href="/profile"
                  >
                    Кабінет
                  </Link>
                  <button
                    className="inline-flex h-11 items-center justify-center rounded-md bg-slate-950 px-4 text-sm font-bold text-white transition hover:bg-slate-800"
                    onClick={handleSignOut}
                    type="button"
                  >
                    Вийти
                  </button>
                </div>
              ) : (
                <button
                  className="inline-flex h-11 w-full items-center justify-center rounded-md bg-slate-950 px-4 text-sm font-bold text-white transition hover:bg-slate-800"
                  onClick={handleOpenAuth}
                  type="button"
                >
                  Увійти
                </button>
              )}
            </div>
          </div>
        </div>
      ) : null}
    </header>
  );
}

export default SiteHeader;
