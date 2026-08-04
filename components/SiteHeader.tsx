'use client';

import Image from 'next/image';
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
      ...extraLinks,
    ],
    [extraLinks],
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
    <header className="sticky top-0 z-40 border-b border-violet-300/20 bg-[#12121a]/85 shadow-[0_10px_30px_rgba(3,3,10,0.32)] backdrop-blur-xl">
      <div
        className={`mx-auto flex w-full ${containerClass} items-center justify-between gap-3 px-4 py-3 sm:px-6`}
      >
        <Link
          className="neo-heading flex min-w-0 items-center gap-2 text-base font-bold tracking-normal text-violet-50 transition hover:text-fuchsia-200 sm:text-lg"
          href="/"
        >
          <span className="grid h-9 w-9 shrink-0 place-items-center overflow-hidden rounded-full border border-amber-300/55 bg-white shadow-[0_0_18px_rgba(192,132,252,0.32)]">
            <Image
              alt=""
              className="h-full w-full object-cover"
              height={36}
              priority
              src="/economic_olympus_logo.png"
              width={36}
            />
          </span>
          <span className="truncate">Economic Olympus</span>
        </Link>

        <nav className="hidden items-center gap-6 text-sm font-semibold text-slate-300 min-[769px]:flex">
          {links.map((link) => {
            const active = isActiveLink(pathname, link.href);

            return (
              <Link
                className={
                  active
                    ? 'text-violet-100 drop-shadow-[0_0_12px_rgba(192,132,252,0.45)]'
                    : 'transition hover:text-fuchsia-200'
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
          className="neo-button inline-grid h-10 w-10 place-items-center rounded-[16px] border border-violet-300/30 bg-[#181824]/85 text-violet-50 shadow-sm transition hover:border-fuchsia-300/70 min-[769px]:hidden"
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
          className="neo-surface border-t border-violet-300/20 bg-[#12121a]/95 shadow-2xl min-[769px]:hidden"
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
                        ? 'bg-violet-500/20 text-violet-50 ring-1 ring-violet-300/40'
                        : 'text-slate-300 hover:bg-violet-500/10 hover:text-violet-50'
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

            <div className="mt-4 border-t border-violet-300/20 pt-4">
              {loading ? (
                <div className="h-11 rounded-[16px] border border-violet-300/20 bg-violet-500/10" />
              ) : user ? (
                <div className="grid gap-3">
                  <div className="neo-panel flex min-w-0 items-center gap-3 rounded-[18px] border border-violet-300/20 p-3">
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
                    className="neo-button inline-flex h-11 items-center justify-center rounded-[16px] border border-violet-300/30 px-4 text-sm font-bold text-violet-50 transition hover:border-fuchsia-300/70"
                    href="/profile"
                  >
                    Кабінет
                  </Link>
                  <button
                    className="neo-button inline-flex h-11 items-center justify-center rounded-[16px] bg-slate-950 px-4 text-sm font-bold text-white transition hover:bg-slate-800"
                    onClick={handleSignOut}
                    type="button"
                  >
                    Вийти
                  </button>
                </div>
              ) : (
                <button
                  className="neo-button inline-flex h-11 w-full items-center justify-center rounded-[16px] bg-slate-950 px-4 text-sm font-bold text-white transition hover:bg-slate-800"
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
