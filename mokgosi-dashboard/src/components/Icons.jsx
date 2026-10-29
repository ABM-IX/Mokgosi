import React from 'react';

/**
 * One small icon set so every control speaks the same visual language: 24 px grid, 1.75 px round strokes,
 * drawn in currentColor so the icons follow the theme. Decorative by default (aria-hidden).
 */
const PATHS = {
  bell: ['M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9', 'M13.73 21a2 2 0 0 1-3.46 0'],
  bellOff: [
    'M13.73 21a2 2 0 0 1-3.46 0',
    'M18.63 13A17.89 17.89 0 0 1 18 8',
    'M6.26 6.26A5.86 5.86 0 0 0 6 8c0 7-3 9-3 9h14',
    'M18 8a6 6 0 0 0-9.33-5',
    'M2 2l20 20',
  ],
  sun: [
    'M12 3v2M12 19v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M3 12h2M19 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42',
  ],
  moon: ['M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z'],
  monitor: ['M8 21h8', 'M12 17v4'],
  camera: ['M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z'],
  map: ['M1 6v16l7-4 8 4 7-4V2l-7 4-8-4-7 4z', 'M8 2v16', 'M16 6v16'],
  chart: ['M12 20V10', 'M18 20V4', 'M6 20v-4'],
  alert: ['M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z', 'M12 9v4', 'M12 17h.01'],
  check: ['M20 6L9 17l-5-5'],
  clock: ['M12 6v6l4 2'],
  phoneOff: [
    'M10.68 13.31a16 16 0 0 0 3.41 2.6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7 2 2 0 0 1 1.72 2v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.42 19.42 0 0 1-3.33-2.67m-2.67-3.34a19.79 19.79 0 0 1-3.07-8.63A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91',
    'M22 2L2 22',
  ],
  lock: ['M7 11V7a5 5 0 0 1 10 0v4'],
  logOut: ['M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4', 'M16 17l5-5-5-5', 'M21 12H9'],
  close: ['M18 6L6 18', 'M6 6l12 12'],
  crosshair: ['M22 12h-4', 'M6 12H2', 'M12 6V2', 'M12 22v-4'],
  layers: ['M12 2L2 7l10 5 10-5-10-5z', 'M2 17l10 5 10-5', 'M2 12l10 5 10-5'],
  shield: ['M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z'],
  arrowRight: ['M5 12h14', 'M12 5l7 7-7 7'],
};

const EXTRA = {
  sun: <circle cx="12" cy="12" r="4" />,
  monitor: <rect x="2" y="3" width="20" height="14" rx="2" />,
  camera: <circle cx="12" cy="13" r="4" />,
  clock: <circle cx="12" cy="12" r="10" />,
  lock: <rect x="3" y="11" width="18" height="11" rx="2" />,
  crosshair: <circle cx="12" cy="12" r="10" />,
};

export default function Icon({ name, size = 18, title, className = '' }) {
  const paths = PATHS[name];
  if (!paths) return null;
  return (
    <svg
      className={`icon ${className}`.trim()}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
      role={title ? 'img' : undefined}
      aria-label={title}
      aria-hidden={title ? undefined : true}
      focusable="false"
    >
      {title && <title>{title}</title>}
      {EXTRA[name]}
      {paths.map((d) => (
        <path key={d} d={d} />
      ))}
    </svg>
  );
}

/** The Mokgosi mark: a signal ping. A call for help (centre) and the connected response spreading out (rings). */
export function BrandMark({ size = 28 }) {
  return (
    <svg className="brand-mark" width={size} height={size} viewBox="0 0 32 32" role="img" aria-label="Mokgosi">
      <rect width="32" height="32" rx="9" className="brand-mark-bg" />
      <circle cx="16" cy="16" r="3.2" fill="#fff" />
      <circle cx="16" cy="16" r="7.4" fill="none" stroke="#fff" strokeWidth="1.8" opacity="0.85" />
      <circle cx="16" cy="16" r="11.6" fill="none" stroke="#fff" strokeWidth="1.8" opacity="0.45" />
    </svg>
  );
}
