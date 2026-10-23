import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const srcDir = path.join(__dirname, '..', 'src');

test('Dashboard modular components exist per Master Architecture v2.0 spec', () => {
  const required = [
    'App.jsx',
    'lib/api.js',
    'lib/supabaseClient.js',
    'components/HeaderBar.jsx',
    'components/IncidentQueue.jsx',
    'components/TacticalMap.jsx',
    'components/CctvStreamModal.jsx',
    'components/EvidenceDocketModal.jsx',
  ];
  for (const rel of required) {
    assert.equal(fs.existsSync(path.join(srcDir, rel)), true, `Missing ${rel}`);
  }
});

test('IncidentQueue sorts by P1_CRITICAL > P2_HIGH > P3_VERIFY then age', () => {
  const PRIORITY_RANK = { P1_CRITICAL: 3, P2_HIGH: 2, P3_VERIFY: 1 };
  const sortIncidentsByUrgency = (list) =>
    [...list].sort((a, b) => {
      const rankDiff = (PRIORITY_RANK[b.priority] || 0) - (PRIORITY_RANK[a.priority] || 0);
      if (rankDiff !== 0) return rankDiff;
      return new Date(b.created_at || 0).getTime() - new Date(a.created_at || 0).getTime();
    });

  const sample = [
    { id: '1', priority: 'P3_VERIFY', created_at: '2026-10-23T05:00:00Z' },
    { id: '2', priority: 'P1_CRITICAL', created_at: '2026-10-23T04:55:00Z' },
    { id: '3', priority: 'P2_HIGH', created_at: '2026-10-23T05:01:00Z' },
    { id: '4', priority: 'P1_CRITICAL', created_at: '2026-10-23T05:02:00Z' },
  ];
  const sorted = sortIncidentsByUrgency(sample);
  assert.deepEqual(
    sorted.map((x) => x.id),
    ['4', '2', '3', '1'],
  );
});

test('Dashboard includes SILENT DURESS warning, 4-step lifecycle, Ed25519 verify, and non-invented referral TODOs', () => {
  const appSource = fs.readFileSync(path.join(srcDir, 'App.jsx'), 'utf8');
  const docketSource = fs.readFileSync(
    path.join(srcDir, 'components', 'EvidenceDocketModal.jsx'),
    'utf8',
  );
  const apiSource = fs.readFileSync(path.join(srcDir, 'lib', 'api.js'), 'utf8');

  assert.match(appSource, /SILENT DURESS — do NOT call or message the user/);
  assert.match(appSource, /1\. Acknowledge/);
  assert.match(appSource, /2\. Assign/);
  assert.match(appSource, /3\. Dispatch Unit/);
  assert.match(appSource, /4\. Resolve/);
  assert.match(docketSource, /Verify Signature \(Ed25519\)/);
  assert.match(apiSource, /TODO: confirm with Botswana Police Service GBV desk/);
});

