// CBFlow Dashboard - JavaScript

const API_BASE = '';

async function fetchAPI(endpoint) {
    try {
        const response = await fetch(`${API_BASE}/api/${endpoint}`);
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        return await response.json();
    } catch (error) {
        console.error(`API error (${endpoint}):`, error);
        return null;
    }
}

// Tab navigation
document.querySelectorAll('.tab').forEach(tab => {
    tab.addEventListener('click', () => {
        document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
        document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
        tab.classList.add('active');
        document.getElementById(tab.dataset.tab).classList.add('active');
    });
});

// Load overview
async function loadOverview() {
    const status = await fetchAPI('status');
    if (status) {
        document.getElementById('project-count').textContent = status.projects || 0;
        document.getElementById('release-count').textContent = status.releases || 0;
        document.getElementById('run-count').textContent = status.runs || 0;
        document.getElementById('core-dir').textContent = status.core_dir || '-';

        const indicator = document.getElementById('status-indicator');
        indicator.textContent = 'Connected';
        indicator.className = 'connected';
    }
    document.getElementById('last-updated').textContent =
        `Updated: ${new Date().toLocaleTimeString()}`;
}

// Load projects
async function loadProjects() {
    const data = await fetchAPI('projects');
    if (!data || !data.projects) return;

    const projects = data.projects;
    let html = '<table><thead><tr><th>Name</th><th>Technology</th><th>Status</th><th>Flows</th><th>Lead</th></tr></thead><tbody>';

    for (const [name, info] of Object.entries(projects)) {
        const flows = (info.enabled_flows || []).map(f =>
            `<span class="badge badge-flow">${f}</span>`
        ).join(' ');
        const status = info.status || 'active';

        html += `<tr>
            <td><strong>${name}</strong></td>
            <td>${info.technology || '-'}</td>
            <td><span class="badge badge-active">${status}</span></td>
            <td>${flows}</td>
            <td>${info.chip_lead || '-'}</td>
        </tr>`;
    }

    html += '</tbody></table>';
    document.getElementById('projects-table').innerHTML = html;
}

// Load runs
async function loadRuns() {
    const runs = await fetchAPI('runs');
    if (!runs) return;

    let html = '<table><thead><tr><th>Run</th><th>Flow</th><th>Phase</th><th>Stages</th><th>Release</th></tr></thead><tbody>';

    for (const run of runs) {
        const stages = run.completed_stages || [];
        const stageStr = stages.length > 0
            ? `${stages.length} completed`
            : 'No stamps';

        html += `<tr>
            <td><strong>${run.name}</strong></td>
            <td><span class="badge badge-flow">${run.flow_type || '-'}</span></td>
            <td>${run.phase || '-'}</td>
            <td><span class="badge badge-completed">${stageStr}</span></td>
            <td>${run.release || '-'}</td>
        </tr>`;
    }

    html += '</tbody></table>';
    document.getElementById('runs-table').innerHTML = html;
}

// Load releases
async function loadReleases() {
    const releases = await fetchAPI('releases');
    if (!releases) return;

    let html = '<table><thead><tr><th>Version</th><th>Created</th><th>Components</th><th>Status</th></tr></thead><tbody>';

    for (const release of releases) {
        const isCurrent = release.current ? '<span class="badge badge-current">current</span>' : '';
        const created = release.created ? release.created.substring(0, 19) : '-';

        html += `<tr>
            <td><strong>${release.version}</strong> ${isCurrent}</td>
            <td>${created}</td>
            <td>${release.components || '-'}</td>
            <td>${release.description || '-'}</td>
        </tr>`;
    }

    html += '</tbody></table>';
    document.getElementById('releases-table').innerHTML = html;
}

// Load metrics
async function loadMetrics() {
    const metrics = await fetchAPI('metrics');
    if (!metrics) {
        document.getElementById('metrics-content').innerHTML = '<p>No metrics data available. Run <code>cbflow flow metrics collect</code> to start collecting.</p>';
        return;
    }

    let html = '';

    // Stage stats
    const stats = metrics.stage_stats || [];
    if (stats.length > 0) {
        html += '<h3>Stage Performance</h3>';
        html += '<table><thead><tr><th>Flow</th><th>Stage</th><th>Runs</th><th>Avg Duration</th><th>Pass Rate</th></tr></thead><tbody>';
        for (const stat of stats) {
            const total = (stat.successes || 0) + (stat.failures || 0);
            const rate = total > 0 ? ((stat.successes / total) * 100).toFixed(1) : '-';
            const avgDur = stat.avg_duration ? `${stat.avg_duration.toFixed(1)}s` : '-';
            html += `<tr><td>${stat.flow_type}</td><td>${stat.stage}</td><td>${stat.runs}</td><td>${avgDur}</td><td>${rate}%</td></tr>`;
        }
        html += '</tbody></table>';
    }

    // Recent runs
    const recent = metrics.recent_runs || [];
    if (recent.length > 0) {
        html += '<h3 style="margin-top:1.5rem">Recent Runs</h3>';
        html += '<table><thead><tr><th>Flow</th><th>Run</th><th>Stages</th><th>Duration</th><th>Status</th></tr></thead><tbody>';
        for (const run of recent) {
            const dur = run.total_duration_seconds;
            const durStr = dur > 3600 ? `${(dur/3600).toFixed(1)}h` : dur > 60 ? `${(dur/60).toFixed(1)}m` : `${dur.toFixed(0)}s`;
            html += `<tr><td>${run.flow_type || '-'}</td><td>${run.run_name || '-'}</td><td>${run.completed_stages}/${run.total_stages}</td><td>${durStr}</td><td>${run.status}</td></tr>`;
        }
        html += '</tbody></table>';
    }

    if (!html) html = '<p>No metrics data available yet.</p>';
    document.getElementById('metrics-content').innerHTML = html;
}

// Initial load
loadOverview();
loadProjects();
loadRuns();
loadReleases();
loadMetrics();

// Auto-refresh every 30 seconds
setInterval(() => {
    loadOverview();
    loadRuns();
    loadMetrics();
}, 30000);
