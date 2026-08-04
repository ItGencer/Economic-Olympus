'use client';

import { useEffect, useRef, useState } from 'react';

import { useLanguage } from '@/components/LanguageProvider';
import {
  localeLabels,
  localeNativeNames,
  SupportedLocale,
  supportedLocales,
} from '@/lib/i18n';

type LanguageSwitcherProps = {
  className?: string;
};

const localeCodes: Record<SupportedLocale, string> = {
  de: 'DE',
  en: 'EN',
  ja: 'JA',
  uk: 'UA',
};

function joinClassNames(...classes: Array<string | false | undefined>) {
  return classes.filter(Boolean).join(' ');
}

export function LanguageSwitcher({ className }: LanguageSwitcherProps) {
  const { locale, setLocale } = useLanguage();
  const [open, setOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    function handlePointerDown(event: PointerEvent) {
      if (!containerRef.current?.contains(event.target as Node)) {
        setOpen(false);
      }
    }

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') {
        setOpen(false);
      }
    }

    document.addEventListener('pointerdown', handlePointerDown);
    document.addEventListener('keydown', handleKeyDown);

    return () => {
      document.removeEventListener('pointerdown', handlePointerDown);
      document.removeEventListener('keydown', handleKeyDown);
    };
  }, []);

  function handleLocaleSelect(nextLocale: SupportedLocale) {
    setLocale(nextLocale);
    setOpen(false);
  }

  return (
    <div
      className={joinClassNames('relative min-w-0', className)}
      data-i18n-ignore="true"
      ref={containerRef}
    >
      <button
        aria-expanded={open}
        aria-haspopup="listbox"
        aria-label={`Change language: ${localeLabels[locale]}`}
        className="neo-button flex h-10 w-full min-w-[78px] items-center justify-center gap-2 rounded-[16px] border border-violet-300/30 bg-[#181824] px-3 text-sm font-black text-violet-50 shadow-[inset_4px_4px_10px_rgba(2,2,8,0.35),inset_-4px_-4px_10px_rgba(192,132,252,0.08)] transition hover:border-fuchsia-300/70"
        onClick={() => setOpen((currentOpen) => !currentOpen)}
        type="button"
      >
        <span className="grid h-6 min-w-9 place-items-center rounded-full border border-violet-300/35 bg-violet-500/15 px-2 text-xs font-black text-fuchsia-100">
          {localeCodes[locale]}
        </span>
        <span
          aria-hidden="true"
          className={joinClassNames(
            'text-[10px] text-slate-400 transition',
            open && 'rotate-180',
          )}
        >
          v
        </span>
      </button>

      {open ? (
        <div
          className="neo-modal-panel absolute right-0 z-50 mt-2 w-56 overflow-hidden rounded-[18px] border border-violet-300/30 bg-[#12121a] p-1.5 shadow-[12px_12px_30px_rgba(2,2,8,0.7),-8px_-8px_22px_rgba(192,132,252,0.14),0_0_30px_rgba(168,85,247,0.24)]"
          role="listbox"
        >
          {supportedLocales.map((supportedLocale) => (
            <button
              aria-selected={supportedLocale === locale}
              className={joinClassNames(
                'flex w-full items-center gap-3 rounded-[14px] px-3 py-2 text-left text-sm font-bold transition',
                supportedLocale === locale
                  ? 'bg-violet-500/25 text-violet-50 ring-1 ring-violet-300/40'
                  : 'text-slate-300 hover:bg-violet-500/14 hover:text-violet-50',
              )}
              key={supportedLocale}
              onClick={() => handleLocaleSelect(supportedLocale)}
              role="option"
              type="button"
            >
              <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full border border-violet-300/30 bg-[#181824] text-xs font-black text-fuchsia-100">
                {localeCodes[supportedLocale]}
              </span>
              <span className="min-w-0 flex-1">
                <span className="block truncate">
                  {localeLabels[supportedLocale]}
                </span>
                <span className="block truncate text-[11px] font-semibold text-slate-400">
                  {localeNativeNames[supportedLocale]}
                </span>
              </span>
              {supportedLocale === locale ? (
                <span className="rounded-full border border-violet-300/30 px-2 py-0.5 text-[11px] text-fuchsia-100">
                  on
                </span>
              ) : null}
            </button>
          ))}
        </div>
      ) : null}
    </div>
  );
}

export default LanguageSwitcher;
