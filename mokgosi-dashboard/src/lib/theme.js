import { useCallback, useEffect, useState } from 'react';

// "system" follows the operating system. The choice is a per-person convenience, so it lives in
// localStorage and every read and write is guarded: private windows and blocked storage must not break the console.
const KEY = 'mokgosi.theme';

function readStored() {
  try {
    const value = window.localStorage.getItem(KEY);
    return value === 'light' || value === 'dark' ? value : 'system';
  } catch {
    return 'system';
  }
}

function systemPrefersDark() {
  return typeof window !== 'undefined' && window.matchMedia?.('(prefers-color-scheme: dark)').matches;
}

function resolve(mode) {
  return mode === 'system' ? (systemPrefersDark() ? 'dark' : 'light') : mode;
}

function apply(resolved) {
  document.documentElement.dataset.theme = resolved;
  const meta = document.querySelector('meta[name="theme-color"]');
  if (meta) meta.setAttribute('content', resolved === 'dark' ? '#0b0d10' : '#f5f5f7');
}

/** Returns the person's choice, the theme actually in effect, and a setter. */
export function useTheme() {
  const [mode, setModeState] = useState(readStored);
  const [resolved, setResolved] = useState(() => resolve(readStored()));

  useEffect(() => {
    const next = resolve(mode);
    setResolved(next);
    apply(next);
    if (mode !== 'system') return undefined;
    const query = window.matchMedia?.('(prefers-color-scheme: dark)');
    if (!query) return undefined;
    const onChange = () => {
      const value = resolve('system');
      setResolved(value);
      apply(value);
    };
    query.addEventListener('change', onChange);
    return () => query.removeEventListener('change', onChange);
  }, [mode]);

  const setMode = useCallback((next) => {
    setModeState(next);
    try {
      if (next === 'system') window.localStorage.removeItem(KEY);
      else window.localStorage.setItem(KEY, next);
    } catch {
      // Storage unavailable: the choice lasts for this visit only.
    }
  }, []);

  return { mode, resolved, setMode };
}
