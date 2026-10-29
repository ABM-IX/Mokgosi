import React, { useEffect, useState } from 'react';
import { DEMO_MODE, fetchHotspots } from '../lib/api.js';
import { DEMO_HOTSPOTS } from '../lib/demoData.js';
import { CATEGORY_LABEL, coords, humanize, label } from '../lib/labels.js';

/** Where incidents cluster, in ~500 m cells. Sparse cells never leave the server, so nobody can be singled out. */
export default function HotspotsView() {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    let mounted = true;
    fetchHotspots()
      .then((res) => mounted && setData(res))
      .catch(() => {
        if (!mounted) return;
        if (DEMO_MODE) setData(DEMO_HOTSPOTS);
        else setError('Area trends could not be loaded. The server did not respond.');
      })
      .finally(() => mounted && setLoading(false));
    return () => {
      mounted = false;
    };
  }, []);

  const cells = data?.hotspots || [];
  const total = cells.reduce((sum, cell) => sum + (cell.incident_count || 0), 0);

  return (
    <section className="card" aria-label="Area trends">
      <div className="card-head">
        <h2>Area trends</h2>
        {cells.length > 0 && (
          <span className="card-note">
            {total} incidents across {cells.length} areas
          </span>
        )}
      </div>
      <p className="muted">
        Locations are rounded to areas about 500 m across. Areas with fewer than 5 incidents (10 for
        gender-based violence) are left out, so no person or home can be picked out.
      </p>

      {loading ? (
        <p className="faint">Loading…</p>
      ) : error ? (
        <p className="muted" role="alert">
          {error}
        </p>
      ) : cells.length === 0 ? (
        <p className="empty">No area has enough incidents to show yet.</p>
      ) : (
        <table className="table">
          <thead>
            <tr>
              <th>Area (approximate centre)</th>
              <th>Type</th>
              <th>Incidents</th>
              <th>Level</th>
            </tr>
          </thead>
          <tbody>
            {cells.map((cell) => (
              <tr key={`${cell.grid_lat}-${cell.grid_lng}-${cell.category}`}>
                <td className="mono">{coords(cell.grid_lat, cell.grid_lng, 3)}</td>
                <td>{label(CATEGORY_LABEL, cell.category)}</td>
                <td className="num">{cell.incident_count}</td>
                <td>{humanize(cell.density_level)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </section>
  );
}
