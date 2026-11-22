// Adaptive polling helper.
//
// Each dashboard page has a primary "refresh" function it wants to call on an
// interval. This helper replaces a fixed `setInterval` with a self-tuning
// loop that speeds up when the run is active and slows down when it's idle.
//
// Cadence comes from flow_registry.tcl, served by the page as window.__cbf.poll:
//   • active runs  → flow(dashboard,poll_active_ms)
//   • idle runs    → flow(dashboard,poll_idle_ms)
//   • after error  → flow(dashboard,poll_error_ms) (temporary back-off)
//
// Activity is derived from `/api/status`, which every dashboard endpoint
// returns cheaply via ETag (304 = no state change since last poll).
//
// Usage:
//   window.CBfAdaptive.start(fn);                 // primary polling loop
//   window.CBfAdaptive.getActivity();             // "active" | "idle" | ""
//
// Set `window.__cbfAdaptiveInterval` before calling start() to override the
// default cadence for that page.

(function () {
  'use strict';

  function _defaults() {
    const p = (window.__cbf || {}).poll;
    if (!p) throw new Error('window.__cbf.poll missing — page was not served by the CBflow dashboard');
    return { active: p.active, idle: p.idle, errorBackoff: p.errorBackoff };
  }

  let _activity = '';
  let _lastEtag = '';

  async function _probeActivity() {
    // Best-effort. 304 = no change since last probe (keep prior activity).
    try {
      const headers = {};
      if (_lastEtag) headers['If-None-Match'] = _lastEtag;
      // Static file: not rewritten by the daemon like the templates are, so
      // prefix the run's /run/<id> scope from the page URL ourselves.
      const scope = (location.pathname.match(/^\/run\/[^\/]+/) || [''])[0];
      const r = await fetch(scope + '/api/status', { headers });
      if (r.status === 304) return;
      if (!r.ok) return;
      const etag = r.headers.get('ETag');
      if (etag) _lastEtag = etag.replace(/"/g, '');
      const body = await r.json();
      if (body && body.run_activity) {
        _activity = body.run_activity;
      }
    } catch (e) { /* network flap — keep prior activity */ }
  }

  function _pickDelay(hadError) {
    const cfg = Object.assign({}, _defaults(), window.__cbfAdaptiveInterval || {});
    if (hadError) return cfg.errorBackoff;
    return _activity === 'idle' ? cfg.idle : cfg.active;
  }

  function start(fn) {
    let hadError = false;
    const tick = async () => {
      hadError = false;
      try {
        // Refresh activity signal alongside the caller's work — activity
        // probe is 304 most of the time, so this costs ~nothing.
        await Promise.all([_probeActivity(), Promise.resolve(fn())]);
      } catch (e) {
        hadError = true;
      }
      setTimeout(tick, _pickDelay(hadError));
    };
    // First tick: run immediately so the page renders without waiting.
    tick();
  }

  window.CBfAdaptive = { start, getActivity: () => _activity };
})();
