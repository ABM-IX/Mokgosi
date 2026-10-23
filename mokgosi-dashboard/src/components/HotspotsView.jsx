import React, { useEffect, useState } from 'react';
import { fetchHotspots } from '../lib/api.js';

/**
 * Coarse Grid Hotspot & Spatial Risk View for Safer Communities.
 * Enforces strict k-anonymity: cells with fewer than 5 incidents are suppressed.
 * No individual user identifiers or fine-grained coordinates are ever exposed.
 */
export default function HotspotsView({ onBackToLiveMap }) {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    let mounted = true;
    (async () => {
      try {
        const res = await fetchHotspots();
        if (mounted) {
          setData(res);
          setLoading(false);
        }
      } catch (err) {
        if (mounted) {
          setError(err.message || 'Failed to load community hotspot analytics.');
          setLoading(false);
        }
      }
    })();
    return () => {
      mounted = false;
    };
  }, []);

  const hotspots = data?.hotspots || [];

  return (
    <section className="panel hotspots-view" aria-label="Community Safety Hotspots">
      <div className="hotspots-header">
        <div>
          <h2>Community Safety Hotspots &amp; Spatial Density</h2>
          <small>Aggregated ~500m coarse grid cells for municipal and community planning.</small>
        </div>
        {onBackToLiveMap && (
          <button type="button" className="btn-outline" onClick={onBackToLiveMap}>
            ← Back to Tactical Live Map
          </button>
        )}
      </div>

      <div className="hotspots-privacy-banner" role="note">
        <strong>🔒 Strict K-Anonymity Privacy Guarantee</strong>
        <p>
          Cells with fewer than 5 incidents (or fewer than 10 GBV incidents) are automatically
          suppressed by the analytics engine. Coordinates are rounded to ~500m coarse grid cells.
          Zero survivor identifiers or private residential addresses are ever disclosed.
        </p>
      </div>

      {loading ? (
        <div className="hotspots-loading">Loading coarse grid analytics...</div>
      ) : error ? (
        <div className="notice" role="alert">
          {error}
        </div>
      ) : hotspots.length === 0 ? (
        <div className="empty-hotspots">
          <p>
            No coarse cells meet the minimum aggregation threshold (≥ 5 incidents) in this period.
          </p>
          <small>All sparse cells were safely suppressed to preserve individual privacy.</small>
        </div>
      ) : (
        <div className="hotspots-grid">
          <div className="hotspots-metrics-row">
            <div className="metric-box">
              <span className="metric-title">Aggregated Grid Cells</span>
              <strong className="metric-number">{hotspots.length}</strong>
            </div>
            <div className="metric-box">
              <span className="metric-title">Total Aggregated Incidents</span>
              <strong className="metric-number">
                {hotspots.reduce((sum, h) => sum + (h.count || 0), 0)}
              </strong>
            </div>
            <div className="metric-box">
              <span className="metric-title">Grid Resolution</span>
              <strong className="metric-number">~500 m</strong>
            </div>
          </div>

          <table className="hotspots-table">
            <thead>
              <tr>
                <th>Coarse Cell Center</th>
                <th>Incident Density</th>
                <th>Primary Categories</th>
                <th>Risk Classification</th>
              </tr>
            </thead>
            <tbody>
              {hotspots.map((cell, idx) => {
                const count = cell.count || 0;
                const riskLevel = count >= 20 ? 'HIGH_DENSITY' : count >= 10 ? 'MODERATE' : 'ELEVATED';
                const riskClass = count >= 20 ? 'risk-high' : count >= 10 ? 'risk-med' : 'risk-low';

                return (
                  <tr key={idx}>
                    <td>
                      <code>
                        {Number(cell.lat).toFixed(3)}, {Number(cell.lng).toFixed(3)}
                      </code>
                    </td>
                    <td>
                      <span className="cell-count-badge">{count} incidents</span>
                    </td>
                    <td>
                      {cell.categories
                        ? Object.entries(cell.categories)
                            .map(([cat, c]) => `${cat}: ${c}`)
                            .join(', ')
                        : 'Mixed Safety Incidents'}
                    </td>
                    <td>
                      <span className={`risk-tag ${riskClass}`}>{riskLevel}</span>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
