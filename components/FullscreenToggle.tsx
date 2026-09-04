'use client';

import { useEffect, useState } from 'react';

type FullscreenDocument = Document & {
  webkitExitFullscreen?: () => Promise<void> | void;
  webkitFullscreenElement?: Element | null;
};

type FullscreenElement = HTMLElement & {
  webkitRequestFullscreen?: () => Promise<void> | void;
};

function readFullscreenElement() {
  const fullscreenDocument = document as FullscreenDocument;

  return (
    document.fullscreenElement ??
    fullscreenDocument.webkitFullscreenElement ??
    null
  );
}

function readFullscreenSupport() {
  if (typeof document === 'undefined') {
    return false;
  }

  const fullscreenDocument = document as FullscreenDocument;
  const fullscreenElement = document.documentElement as FullscreenElement;

  return Boolean(
    fullscreenElement.requestFullscreen ||
      fullscreenElement.webkitRequestFullscreen ||
      document.exitFullscreen ||
      fullscreenDocument.webkitExitFullscreen,
  );
}

async function requestPageFullscreen() {
  const fullscreenElement = document.documentElement as FullscreenElement;

  if (fullscreenElement.requestFullscreen) {
    await fullscreenElement.requestFullscreen();
    return;
  }

  await fullscreenElement.webkitRequestFullscreen?.();
}

async function exitPageFullscreen() {
  const fullscreenDocument = document as FullscreenDocument;

  if (document.exitFullscreen) {
    await document.exitFullscreen();
    return;
  }

  await fullscreenDocument.webkitExitFullscreen?.();
}

function ExpandIcon() {
  return (
    <svg
      aria-hidden="true"
      className="h-5 w-5"
      fill="none"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="2.2"
      viewBox="0 0 24 24"
    >
      <path d="M8 3H3v5" />
      <path d="M3 3l6 6" />
      <path d="M16 3h5v5" />
      <path d="M21 3l-6 6" />
      <path d="M8 21H3v-5" />
      <path d="M3 21l6-6" />
      <path d="M16 21h5v-5" />
      <path d="M21 21l-6-6" />
    </svg>
  );
}

function CollapseIcon() {
  return (
    <svg
      aria-hidden="true"
      className="h-5 w-5"
      fill="none"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="2.2"
      viewBox="0 0 24 24"
    >
      <path d="M9 3v6H3" />
      <path d="M3 9l6-6" />
      <path d="M15 3v6h6" />
      <path d="M21 9l-6-6" />
      <path d="M9 21v-6H3" />
      <path d="M3 15l6 6" />
      <path d="M15 21v-6h6" />
      <path d="M21 15l-6 6" />
    </svg>
  );
}

export default function FullscreenToggle() {
  const [fullscreen, setFullscreen] = useState(false);
  const [supported, setSupported] = useState(false);

  useEffect(() => {
    function syncFullscreenState() {
      setFullscreen(Boolean(readFullscreenElement()));
    }

    setSupported(readFullscreenSupport());
    syncFullscreenState();

    document.addEventListener('fullscreenchange', syncFullscreenState);
    document.addEventListener('webkitfullscreenchange', syncFullscreenState);

    return () => {
      document.removeEventListener('fullscreenchange', syncFullscreenState);
      document.removeEventListener('webkitfullscreenchange', syncFullscreenState);
    };
  }, []);

  async function handleToggleFullscreen() {
    if (!supported) {
      return;
    }

    try {
      if (readFullscreenElement()) {
        await exitPageFullscreen();
      } else {
        await requestPageFullscreen();
      }
    } catch {
      return;
    } finally {
      setFullscreen(Boolean(readFullscreenElement()));
    }
  }

  const label = fullscreen
    ? 'Згорнути з повного екрана'
    : 'Розгорнути на весь екран';

  return (
    <div
      className="fixed z-[90] opacity-45 transition-opacity duration-200 hover:opacity-100 focus-within:opacity-100"
      style={{
        right: 'max(0.75rem, env(safe-area-inset-right))',
        top: 'max(0.75rem, env(safe-area-inset-top))',
      }}
    >
      <button
        aria-label={label}
        className="grid h-11 w-11 place-items-center rounded-[14px] border border-violet-300/45 bg-slate-950/75 text-violet-50 shadow-[0_12px_30px_rgba(2,2,8,0.45),0_0_22px_rgba(168,85,247,0.22)] backdrop-blur-md transition hover:border-fuchsia-200 hover:bg-violet-500/25 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-fuchsia-200 disabled:cursor-not-allowed disabled:opacity-40"
        disabled={!supported}
        onClick={handleToggleFullscreen}
        title={label}
        type="button"
      >
        {fullscreen ? <CollapseIcon /> : <ExpandIcon />}
      </button>
    </div>
  );
}
