'use client';

import {
  createContext,
  ReactNode,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';

import {
  defaultLocale,
  isSupportedLocale,
  SupportedLocale,
  translatePhrase,
} from '@/lib/i18n';

type LanguageContextValue = {
  locale: SupportedLocale;
  setLocale: (locale: SupportedLocale) => void;
  t: (source: string, options?: { allowPartial?: boolean }) => string;
};

const LanguageContext = createContext<LanguageContextValue | null>(null);
const storageKey = 'economic-olympus-locale';
const translatedAttributes = ['aria-label', 'placeholder', 'title'] as const;

function readInitialLocale() {
  if (typeof window === 'undefined') {
    return defaultLocale;
  }

  const storedLocale = window.localStorage.getItem(storageKey);

  if (storedLocale && isSupportedLocale(storedLocale)) {
    return storedLocale;
  }

  const browserLocale = window.navigator.language.slice(0, 2);

  return isSupportedLocale(browserLocale) ? browserLocale : defaultLocale;
}

function shouldSkipElement(element: Element | null) {
  return Boolean(
    element?.closest(
      'script, style, noscript, svg, canvas, [data-i18n-ignore]',
    ),
  );
}

function translateDocument(
  locale: SupportedLocale,
  textOriginals: WeakMap<Text, string>,
  attributeOriginals: WeakMap<Element, Map<string, string>>,
) {
  const root = document.body;

  if (!root) {
    return;
  }

  function translateTextNode(node: Text) {
    if (shouldSkipElement(node.parentElement)) {
      return;
    }

    if (!textOriginals.has(node)) {
      textOriginals.set(node, node.nodeValue ?? '');
    }

    const source = textOriginals.get(node) ?? '';
    const translated = translatePhrase(source, locale, { allowPartial: true });

    if (node.nodeValue !== translated) {
      node.nodeValue = translated;
    }
  }

  function translateElementAttributes(element: Element) {
    if (shouldSkipElement(element)) {
      return;
    }

    let originalAttributes = attributeOriginals.get(element);

    if (!originalAttributes) {
      originalAttributes = new Map<string, string>();
      attributeOriginals.set(element, originalAttributes);
    }

    for (const attribute of translatedAttributes) {
      const value = element.getAttribute(attribute);

      if (!value) {
        continue;
      }

      if (!originalAttributes.has(attribute)) {
        originalAttributes.set(attribute, value);
      }

      const source = originalAttributes.get(attribute) ?? value;
      const translated = translatePhrase(source, locale, { allowPartial: true });

      if (value !== translated) {
        element.setAttribute(attribute, translated);
      }
    }
  }

  function translateTree(node: Node) {
    if (node.nodeType === Node.TEXT_NODE) {
      translateTextNode(node as Text);
      return;
    }

    if (node.nodeType !== Node.ELEMENT_NODE) {
      return;
    }

    const element = node as Element;

    if (shouldSkipElement(element)) {
      return;
    }

    translateElementAttributes(element);

    const walker = document.createTreeWalker(
      element,
      NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT,
      {
        acceptNode(currentNode) {
          if (
            currentNode.nodeType === Node.ELEMENT_NODE &&
            shouldSkipElement(currentNode as Element)
          ) {
            return NodeFilter.FILTER_REJECT;
          }

          return NodeFilter.FILTER_ACCEPT;
        },
      },
    );

    let currentNode: Node | null = walker.currentNode;

    while (currentNode) {
      if (currentNode.nodeType === Node.TEXT_NODE) {
        translateTextNode(currentNode as Text);
      } else if (currentNode.nodeType === Node.ELEMENT_NODE) {
        translateElementAttributes(currentNode as Element);
      }

      currentNode = walker.nextNode();
    }
  }

  translateTree(root);

  return translateTree;
}

function DomTranslator({ locale }: { locale: SupportedLocale }) {
  const translateTreeRef = useRef<ReturnType<typeof translateDocument> | null>(
    null,
  );
  const textOriginalsRef = useRef(new WeakMap<Text, string>());
  const attributeOriginalsRef = useRef(new WeakMap<Element, Map<string, string>>());
  const translatingRef = useRef(false);

  useEffect(() => {
    document.documentElement.lang = locale;
    window.localStorage.setItem(storageKey, locale);
  }, [locale]);

  useEffect(() => {
    translatingRef.current = true;
    translateTreeRef.current =
      translateDocument(
        locale,
        textOriginalsRef.current,
        attributeOriginalsRef.current,
      ) ?? null;
    translatingRef.current = false;

    const observer = new MutationObserver((mutations) => {
      if (translatingRef.current) {
        return;
      }

      translatingRef.current = true;

      for (const mutation of mutations) {
        if (mutation.type === 'characterData') {
          translateTreeRef.current?.(mutation.target);
          continue;
        }

        mutation.addedNodes.forEach((node) => {
          translateTreeRef.current?.(node);
        });

        if (
          mutation.type === 'attributes' &&
          mutation.target.nodeType === Node.ELEMENT_NODE
        ) {
          translateTreeRef.current?.(mutation.target);
        }
      }

      translatingRef.current = false;
    });

    observer.observe(document.body, {
      attributeFilter: [...translatedAttributes],
      attributes: true,
      characterData: true,
      childList: true,
      subtree: true,
    });

    return () => observer.disconnect();
  }, [locale]);

  return null;
}

export function LanguageProvider({ children }: { children: ReactNode }) {
  const [locale, setLocaleState] = useState<SupportedLocale>(defaultLocale);

  useEffect(() => {
    setLocaleState(readInitialLocale());
  }, []);

  const setLocale = useCallback((nextLocale: SupportedLocale) => {
    setLocaleState(nextLocale);
  }, []);

  const t = useCallback(
    (source: string, options?: { allowPartial?: boolean }) =>
      translatePhrase(source, locale, options),
    [locale],
  );

  const value = useMemo(
    () => ({
      locale,
      setLocale,
      t,
    }),
    [locale, setLocale, t],
  );

  return (
    <LanguageContext.Provider value={value}>
      {children}
      <DomTranslator locale={locale} />
    </LanguageContext.Provider>
  );
}

export function useLanguage() {
  const value = useContext(LanguageContext);

  if (!value) {
    throw new Error('useLanguage must be used inside LanguageProvider.');
  }

  return value;
}

export default LanguageProvider;
