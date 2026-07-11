<script lang="ts">
  import { onMount } from "svelte";
  import { invoke } from "@tauri-apps/api/core";
  import { listen } from "@tauri-apps/api/event";

  // State management
  let daemonStatus = $state("Stopped");
  let rulesVersion = $state(0);
  let rulesTimestamp = $state("N/A");
  let activeProcesses = $state(0);
  let lsmActive = $state(false);
  let targetReleasePid = $state("");
  let logsText = $state("");
  let alertsList = $state<any[]>([]);
  let feedbackMessage = $state("");
  let feedbackType = $state("info"); // info, success, error

  // Weather state engine
  let weatherState = $derived(
    daemonStatus === "Stopped" 
      ? "overcast" 
      : alertsList.some(a => (a.severity && a.severity === 'ALERT') || (typeof a === 'string' && a.includes('ALERT')))
        ? "storm" 
        : activeProcesses > 120 
          ? "rain" 
          : "clear"
  );

  let lightningActive = $state(false);
  let sweepActive = $state(false);

  // HTML5 Rain Canvas Reference
  let canvasEl: HTMLCanvasElement;

  // Reactively apply CSS variables to document root
  $effect(() => {
    const root = document.documentElement;
    const state = weatherState;
    root.style.setProperty('--weather-state', state);
    
    if (state === 'clear') {
      root.style.setProperty('--sky-top', '#090d16');
      root.style.setProperty('--sky-bottom', '#02040a');
      root.style.setProperty('--fog-opacity', '0.35');
      root.style.setProperty('--fog-rise', '25%');
      root.style.setProperty('--cloud-opacity', '0.2');
      root.style.setProperty('--cloud-speed', '30s');
      root.style.setProperty('--glass-bg', 'rgba(12, 18, 30, 0.64)');
      root.style.setProperty('--glass-border-alpha', '0.15');
      root.style.setProperty('--glass-moisture', '0');
      root.style.setProperty('--status-pulse-color', '#10b981');
      root.style.setProperty('--status-pulse-speed', '4s');
      root.style.setProperty('--canvas-rain-active', '0');
    } else if (state === 'overcast') {
      root.style.setProperty('--sky-top', '#141920');
      root.style.setProperty('--sky-bottom', '#0d1016');
      root.style.setProperty('--fog-opacity', '0.60');
      root.style.setProperty('--fog-rise', '45%');
      root.style.setProperty('--cloud-opacity', '0.55');
      root.style.setProperty('--cloud-speed', '24s');
      root.style.setProperty('--glass-bg', 'rgba(14, 20, 32, 0.7)');
      root.style.setProperty('--glass-border-alpha', '0.08');
      root.style.setProperty('--glass-moisture', '0.35');
      root.style.setProperty('--status-pulse-color', '#94a3b8');
      root.style.setProperty('--status-pulse-speed', '4s');
      root.style.setProperty('--canvas-rain-active', '0');
    } else if (state === 'rain') {
      root.style.setProperty('--sky-top', '#0c1018');
      root.style.setProperty('--sky-bottom', '#080b12');
      root.style.setProperty('--fog-opacity', '0.72');
      root.style.setProperty('--fog-rise', '60%');
      root.style.setProperty('--cloud-opacity', '0.75');
      root.style.setProperty('--cloud-speed', '18s');
      root.style.setProperty('--glass-bg', 'rgba(14, 20, 32, 0.72)');
      root.style.setProperty('--glass-border-alpha', '0.07');
      root.style.setProperty('--glass-moisture', '0.70');
      root.style.setProperty('--status-pulse-color', '#06b6d4');
      root.style.setProperty('--status-pulse-speed', '4s');
      root.style.setProperty('--canvas-rain-active', '1');
    } else if (state === 'storm') {
      root.style.setProperty('--sky-top', '#050508');
      root.style.setProperty('--sky-bottom', '#020204');
      root.style.setProperty('--fog-opacity', '0.88');
      root.style.setProperty('--fog-rise', '80%');
      root.style.setProperty('--cloud-opacity', '0.90');
      root.style.setProperty('--cloud-speed', '9s');
      root.style.setProperty('--glass-bg', 'rgba(10, 10, 18, 0.78)');
      root.style.setProperty('--glass-border-alpha', '0.12');
      root.style.setProperty('--glass-moisture', '0.95');
      root.style.setProperty('--status-pulse-color', '#f43f5e');
      root.style.setProperty('--status-pulse-speed', '0.8s');
      root.style.setProperty('--canvas-rain-active', '1');
    }
  });

  // Query stats from the daemon
  async function refreshStats() {
    try {
      const resp = await invoke("get_agent_status") as any;
      if (resp.status === "Success" || resp.payload) {
        const payload = resp.payload || {};
        daemonStatus = "Running";
        rulesVersion = payload.rules_version || 0;
        if (payload.rules_timestamp) {
          rulesTimestamp = new Date(payload.rules_timestamp * 1000).toLocaleString();
        } else {
          rulesTimestamp = "N/A";
        }
        activeProcesses = payload.active_processes || 0;
        lsmActive = payload.lsm_active || false;
      } else {
        daemonStatus = "Stopped";
      }
    } catch (err) {
      daemonStatus = "Stopped";
      lsmActive = false;
      rulesVersion = 0;
      activeProcesses = 0;
    }
    await fetchLogs();
  }

  // Reload rules in the agent
  async function reloadRules() {
    triggerSweep();
    try {
      const resp = await invoke("reload_agent_rules") as any;
      if (resp.status === "Success") {
        showFeedback("Rules reloaded successfully!", "success");
        await refreshStats();
      } else {
        showFeedback(`Failed to reload rules: ${resp.payload || "Unknown error"}`, "error");
      }
    } catch (err) {
      showFeedback(`FFI error: ${err}`, "error");
    }
  }

  // Release containment for PID
  async function releasePid() {
    if (!targetReleasePid) {
      showFeedback("Please enter a valid PID to release.", "error");
      return;
    }
    const pidVal = parseInt(targetReleasePid);
    if (isNaN(pidVal)) {
      showFeedback("PID must be a numeric value.", "error");
      return;
    }

    try {
      const resp = await invoke("release_containment", { pid: pidVal }) as any;
      if (resp.status === "Success") {
        showFeedback(`Successfully released containment for PID ${pidVal}`, "success");
        targetReleasePid = "";
        await refreshStats();
      } else {
        showFeedback(`Error: ${resp.payload || "PID not found or not suspended"}`, "error");
      }
    } catch (err) {
      showFeedback(`Socket error: ${err}`, "error");
    }
  }

  // Fetch telemetry logs
  async function fetchLogs() {
    try {
      const logs = await invoke("get_agent_logs") as string;
      logsText = logs;
      
      const parsedLines = [];
      for (const line of logs.split("\n")) {
        const trimmed = line.trim();
        if (trimmed) {
          const parsed = parseLogLine(trimmed);
          if (parsed) {
            parsedLines.push(parsed);
          } else {
            parsedLines.push(trimmed);
          }
        }
      }
      alertsList = parsedLines;
    } catch (err) {
      logsText = `Failed to fetch logs: ${err}`;
      alertsList = [`Failed to fetch logs: ${err}`];
    }
  }

  // Display toast feedback messages
  function showFeedback(msg: string, type: "info" | "success" | "error" = "info") {
    feedbackMessage = msg;
    feedbackType = type;
    setTimeout(() => {
      if (feedbackMessage === msg) {
        feedbackMessage = "";
      }
    }, 4000);
  }

  function parseLogLine(line: string) {
    try {
      return JSON.parse(line);
    } catch (e) {
      return null;
    }
  }

  function triggerSweep() {
    sweepActive = true;
    setTimeout(() => {
      sweepActive = false;
    }, 900);
  }

  function triggerLightning() {
    if (weatherState !== 'storm') return;
    lightningActive = true;
    setTimeout(() => {
      lightningActive = false;
    }, 400);
  }

  onMount(() => {
    refreshStats();
    const interval = setInterval(refreshStats, 3000);

    // Spontaneous lightning flash timer
    const lightningInterval = setInterval(() => {
      if (Math.random() < 0.3) {
        triggerLightning();
      }
    }, 6000);

    let unlistenAlert: any;
    listen<any>("alert", (event) => {
      const alert = event.payload;
      // Prepend new alert to alertsList
      alertsList = [alert, ...alertsList];
      
      // Trigger lightning flash reactively if alert is high-severity
      if (alert.severity === "ALERT") {
        triggerSweep();
        triggerLightning();
      }
    }).then(unsub => {
      unlistenAlert = unsub;
    });

    // Rain drop canvas rendering
    let drops: Array<{x: number, y: number, r: number, vy: number, vx: number, active: boolean}> = [];
    let animationFrameId: number;

    if (canvasEl) {
      const ctx = canvasEl.getContext('2d');
      if (ctx) {
        canvasEl.width = window.innerWidth;
        canvasEl.height = window.innerHeight;

        const handleResize = () => {
          if (canvasEl) {
            canvasEl.width = window.innerWidth;
            canvasEl.height = window.innerHeight;
          }
        };
        window.addEventListener('resize', handleResize);

        const render = () => {
          ctx.clearRect(0, 0, canvasEl.width, canvasEl.height);
          const active = document.documentElement.style.getPropertyValue('--canvas-rain-active') === '1';
          
          if (active) {
            // Spawn droplets
            const maxDrops = weatherState === 'storm' ? 120 : 60;
            if (drops.length < maxDrops && Math.random() < (weatherState === 'storm' ? 0.6 : 0.2)) {
              drops.push({
                x: Math.random() * canvasEl.width,
                y: -10,
                r: 1.5 + Math.random() * 2.5,
                vy: 5 + Math.random() * 6,
                vx: -0.4 + Math.random() * 0.8,
                active: true
              });
            }

            // Draw droplets
            drops.forEach(d => {
              if (!d.active) return;
              d.y += d.vy;
              d.x += d.vx;
              if (d.y > canvasEl.height) {
                d.active = false;
              } else {
                ctx.beginPath();
                ctx.arc(d.x, d.y, d.r, 0, Math.PI * 2);
                ctx.fillStyle = 'rgba(160, 190, 220, 0.28)';
                ctx.fill();
              }
            });

            drops = drops.filter(d => d.active);
          } else {
            drops = [];
          }

          animationFrameId = requestAnimationFrame(render);
        };
        render();

        return () => {
          window.removeEventListener('resize', handleResize);
          cancelAnimationFrame(animationFrameId);
          clearInterval(interval);
          clearInterval(lightningInterval);
          if (unlistenAlert) unlistenAlert();
        };
      }
    }

    return () => {
      clearInterval(interval);
      clearInterval(lightningInterval);
      if (unlistenAlert) unlistenAlert();
    };
  });
</script>

<!-- Ambient Weather Sky Elements -->
<div class="sky-background"></div>
<div class="star-field" style="opacity: {weatherState === 'clear' ? 0.25 : 0}"></div>
<div class="fog-layer"></div>
<div class="cloud-blob cloud-1"></div>
<div class="cloud-blob cloud-2"></div>

<!-- Lightning Flashing overlay -->
<div class="lightning-flash {lightningActive ? 'lightning-active' : ''}"></div>

<!-- 2D Rain Canvas Simulation -->
<canvas bind:this={canvasEl} class="fixed inset-0 z-15 pointer-events-none"></canvas>

<!-- Screen shake wrapper matching storm lighting effect -->
<div class="shake-wrapper min-h-screen z-20 relative p-6 text-slate-100 flex flex-col gap-6 {lightningActive ? 'shake-active' : ''}">
  
  <!-- Navigation header -->
  <header class="glass-card p-5 flex justify-between items-center relative overflow-hidden">
    <div class="flex items-center gap-3">
      <div class="h-10 w-10 rounded-lg bg-indigo-600/40 flex items-center justify-center font-bold text-white shadow-lg border border-indigo-400/30">
        K
      </div>
      <div>
        <h1 class="text-xl font-bold tracking-tight bg-gradient-to-r from-indigo-300 via-cyan-200 to-emerald-300 bg-clip-text text-transparent">
          Kinnector Security Dashboard
        </h1>
        <p class="text-xs text-slate-400 font-mono uppercase tracking-wider">Atmosphere: {weatherState}</p>
      </div>
    </div>
    <div class="flex gap-3">
      <button 
        onclick={refreshStats} 
        class="px-4 py-2 text-sm rounded bg-slate-800/60 hover:bg-slate-700/80 border border-slate-700/50 transition cursor-pointer font-medium"
      >
        Refresh System
      </button>
      <button 
        onclick={reloadRules} 
        class="px-4 py-2 text-sm rounded bg-indigo-600/80 hover:bg-indigo-500 border border-indigo-400/40 transition shadow-lg shadow-indigo-600/20 cursor-pointer font-medium"
      >
        Wipe & Sync Policies
      </button>
    </div>

    <!-- Hover sweep wiper effect indicator -->
    <div class="surface-sweep {sweepActive ? 'sweep-active' : ''}"></div>
  </header>

  <!-- Notification Toast feedback -->
  {#if feedbackMessage}
    <div class="fixed top-6 right-6 z-50 animate-bounce">
      <div class="px-4 py-3 rounded-lg shadow-2xl border flex items-center gap-2 text-sm max-w-sm backdrop-blur-md
        {feedbackType === 'success' ? 'bg-emerald-950/80 text-emerald-300 border-emerald-800' : ''}
        {feedbackType === 'error' ? 'bg-rose-950/80 text-rose-300 border-rose-800' : ''}
        {feedbackType === 'info' ? 'bg-slate-900/80 text-slate-300 border-slate-700' : ''}
      ">
        <span>{feedbackMessage}</span>
      </div>
    </div>
  {/if}

  <!-- Main System Layout -->
  <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
    
    <!-- Left Column: Metrics and Containment controls -->
    <div class="lg:col-span-1 flex flex-col gap-6">
      
      <!-- Metrics Card -->
      <section class="glass-card p-5">
        <h2 class="text-sm font-semibold text-slate-400 mb-4 tracking-wider uppercase">Daemon Diagnostics</h2>
        
        <div class="flex flex-col gap-4 font-mono text-xs">
          <!-- Status -->
          <div class="flex justify-between items-center border-b border-slate-800/50 pb-3">
            <span class="text-slate-400">Agent Status</span>
            <div class="flex items-center gap-2">
              <span class="h-2 w-2 rounded-full {weatherState === 'storm' ? 'status-dot-urgent' : 'status-dot-calm'}"></span>
              <span class="text-sm font-bold {daemonStatus === 'Running' ? 'text-emerald-400' : 'text-rose-400'}">
                {daemonStatus}
              </span>
            </div>
          </div>

          <!-- Rules Version -->
          <div class="flex justify-between items-center border-b border-slate-800/50 pb-3">
            <span class="text-slate-400">Rules Version</span>
            <span class="text-sm font-semibold text-slate-200">{rulesVersion}</span>
          </div>

          <!-- Rules Timestamp -->
          <div class="flex justify-between items-center border-b border-slate-800/50 pb-3">
            <span class="text-slate-400">Policies Compiled</span>
            <span class="text-slate-300 truncate max-w-[180px]">{rulesTimestamp}</span>
          </div>

          <!-- Tracked Processes -->
          <div class="flex justify-between items-center border-b border-slate-800/50 pb-3">
            <span class="text-slate-400">Tracked Processes</span>
            <span class="text-sm font-semibold text-slate-200">{activeProcesses}</span>
          </div>

          <!-- LSM State -->
          <div class="flex justify-between items-center pb-1">
            <span class="text-slate-400">Kernel Enforced</span>
            <span class="text-sm font-semibold {lsmActive ? 'text-cyan-400' : 'text-amber-500'}">
              {lsmActive ? "BPF LSM Mode" : "User-mode Fallback"}
            </span>
          </div>
        </div>
      </section>

      <!-- LSM Warning Panel (Conditional) -->
      {#if !lsmActive && daemonStatus === 'Running'}
        <section class="glass-card p-5 border-l-4 border-l-amber-500 bg-amber-950/15">
          <div class="flex gap-3">
            <span class="text-xl">⚠️</span>
            <div>
              <h3 class="text-sm font-bold text-amber-400">BPF LSM fallback active</h3>
              <p class="text-xs text-amber-300/80 mt-1 leading-relaxed">
                The agent is currently running with user-space telemetry. This mode is prone to TOCTOU race conditions and timing bugs.
              </p>
              <div class="mt-3 bg-slate-950/80 p-2 rounded text-slate-300 font-mono text-[10px] border border-slate-800">
                sudo antitheft-cli lsm-enable
              </div>
            </div>
          </div>
        </section>
      {/if}

      <!-- Containment Release Panel -->
      <section class="glass-card p-5 {weatherState === 'storm' ? 'quarantined-frozen' : ''}" style="--frost-progress: {weatherState === 'storm' ? 0.7 : 0}">
        <h2 class="text-sm font-semibold text-slate-400 mb-4 tracking-wider uppercase">Active Containments</h2>
        <p class="text-xs text-slate-400 mb-4 leading-relaxed">
          Release suspended process trees (SIGSTOP containment) by targeting the tree's root process ID:
        </p>
        
        <div class="flex gap-2">
          <input 
            type="text" 
            placeholder="Enter PID..." 
            bind:value={targetReleasePid}
            class="flex-1 px-3 py-2 bg-slate-950/70 border border-slate-800 rounded text-sm text-slate-200 outline-none focus:border-indigo-500 transition font-mono"
          />
          <button 
            onclick={releasePid}
            class="px-4 py-2 bg-indigo-600/80 hover:bg-indigo-500 border border-indigo-400/40 rounded text-sm font-medium transition cursor-pointer"
          >
            Release
          </button>
        </div>
      </section>

    </div>

    <!-- Right Column: Live EDR Event Log Reader -->
    <div class="lg:col-span-2 flex flex-col gap-6">
      <section class="glass-card p-5 flex-1 flex flex-col min-h-[500px]">
        <div class="flex justify-between items-center mb-4 pb-3 border-b border-slate-800/50">
          <div>
            <h2 class="text-sm font-semibold text-slate-400 tracking-wider uppercase">Live Telemetry Alert Logs</h2>
            <p class="text-xs text-slate-400">Real-time alerts and admin events from /var/log/kinnector/alerts.log</p>
          </div>
          <button 
            onclick={fetchLogs}
            class="px-3 py-1.5 text-xs bg-slate-800/50 hover:bg-slate-700 border border-slate-700/50 rounded transition font-medium cursor-pointer"
          >
            Flush / Refresh Logs
          </button>
        </div>

        <div class="flex-1 bg-slate-950/80 rounded-lg p-4 font-mono text-xs overflow-y-auto max-h-[500px] border border-slate-900 flex flex-col gap-2">
          {#if alertsList.length > 0}
            {#each alertsList as alertItem}
              {#if alertItem}
                {#if typeof alertItem === 'object'}
                  <div class="py-2.5 px-3 rounded border-l-3 mb-1 flex flex-col gap-1.5 backdrop-blur-sm text-left
                    {alertItem.severity === 'ALERT' ? 'bg-rose-950/15 text-rose-200 border-l-rose-500 border border-rose-950/30' : ''}
                    {alertItem.severity === 'INFO' ? 'bg-blue-950/15 text-blue-200 border-l-blue-500 border border-blue-950/30' : ''}
                    {alertItem.severity === 'WARN' ? 'bg-amber-950/15 text-amber-200 border-l-amber-500 border border-amber-950/30' : ''}
                  ">
                    <div class="flex justify-between items-center text-[10px] text-slate-400 font-semibold font-mono">
                      <span class="flex items-center gap-2">
                        <span>[{new Date(alertItem.ts).toLocaleTimeString()}]</span>
                        <span class="uppercase font-bold tracking-wider rounded px-1.5 py-0.5 text-[9px]
                          {alertItem.severity === 'ALERT' ? 'bg-rose-900/40 text-rose-300' : 'bg-slate-800 text-slate-300'}
                        ">{alertItem.severity}</span>
                      </span>
                      <span>Category: <span class="text-indigo-300 font-bold">{alertItem.category}</span></span>
                    </div>
                    <div class="text-xs font-bold text-slate-200">{alertItem.message}</div>
                    {#if alertItem.process && alertItem.process.pid}
                      <div class="p-2 bg-slate-950/80 rounded border border-slate-800/60 font-mono text-[10px] text-slate-300 flex flex-col gap-1 leading-relaxed">
                        <div><span class="text-slate-500 font-bold">Image:</span> <span class="text-indigo-200">{alertItem.process.exe}</span></div>
                        {#if alertItem.process.cmdline}
                          <div><span class="text-slate-500 font-bold">Command:</span> <span class="text-slate-400">{alertItem.process.cmdline}</span></div>
                        {/if}
                        <div class="flex gap-4 mt-0.5">
                          <span><span class="text-slate-500 font-bold">PID:</span> <span class="text-emerald-400">{alertItem.process.pid}</span></span>
                          <span><span class="text-slate-500 font-bold">PPID:</span> <span class="text-slate-400">{alertItem.process.ppid}</span></span>
                          <span><span class="text-slate-500 font-bold">Action:</span> <span class="text-amber-400 font-bold">{alertItem.action}</span></span>
                          {#if alertItem.rule_path}
                            <span class="truncate max-w-[200px]"><span class="text-slate-500 font-bold">Path:</span> <span class="text-cyan-400 font-mono">{alertItem.rule_path}</span></span>
                          {/if}
                        </div>
                      </div>
                    {/if}
                  </div>
                {#else}
                  <!-- Raw text fallback -->
                  <div class="py-1 px-2 rounded border-l-2
                    {alertItem.includes('ALERT') ? 'bg-rose-950/20 text-rose-400 border-l-rose-500' : ''}
                    {alertItem.includes('INFO') ? 'bg-blue-950/20 text-blue-400 border-l-blue-500' : ''}
                    {!alertItem.includes('ALERT') && !alertItem.includes('INFO') ? 'text-slate-300 border-l-slate-600' : ''}
                  ">
                    {alertItem}
                  </div>
                {/if}
              {/if}
            {/each}
          {:else}
            <div class="text-slate-500 italic text-center py-20">
              No alert logs registered yet. Trigger a threat scenario to log events.
            </div>
          {/if}
        </div>
      </section>
    </div>
  </div>
</div>
