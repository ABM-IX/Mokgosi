import React from 'react';
import { PRIORITY_COLOR } from '../lib/mapStyle.js';

/** The same shape-plus-colour mark used on the map, so a priority reads the same everywhere. */
export default function PriorityGlyph({ priority, size = 20 }) {
  const color = PRIORITY_COLOR[priority] || PRIORITY_COLOR.P3_VERIFY;
  return (
    <svg viewBox="0 0 32 32" width={size} height={size} aria-hidden="true" className="priority-glyph">
      {priority === 'P1_CRITICAL' && (
        <>
          <circle cx="16" cy="16" r="13" fill={color} />
          <path d="M16 9.5v9" stroke="#fff" strokeWidth="3" strokeLinecap="round" />
          <circle cx="16" cy="23" r="1.9" fill="#fff" />
        </>
      )}
      {priority === 'P2_HIGH' && (
        <>
          <path d="M16 4.2 28.6 26.2H3.4Z" fill={color} stroke={color} strokeWidth="3" strokeLinejoin="round" />
          <path d="M16 12.5v6.2" stroke="#fff" strokeWidth="2.6" strokeLinecap="round" />
          <circle cx="16" cy="22.4" r="1.6" fill="#fff" />
        </>
      )}
      {priority !== 'P1_CRITICAL' && priority !== 'P2_HIGH' && (
        <>
          <circle cx="16" cy="16" r="12" fill={color} />
          <path d="M10.6 16.4l3.8 3.8 7-7.6" fill="none" stroke="#fff" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round" />
        </>
      )}
    </svg>
  );
}
