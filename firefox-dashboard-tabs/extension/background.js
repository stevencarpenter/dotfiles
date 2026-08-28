"use strict";

// Opens each configured dashboard set as its own collapsed tab group.
//
// Tabs are created discarded, so a group costs nothing at startup and a
// dashboard whose backend is down (hippo's Grafana only runs when the OTel
// stack is up) shows a placeholder rather than a connection error. Firefox
// only permits a caller-supplied tab title when the tab is discarded, which
// is why every tab carries its dashboard name from dashboards.json.

const CONFIG_PATH = "dashboards.json";
const STATE_KEY = "managedGroups";
const TAB_MARKER_KEY = "dashboard-tabs-owner";
const STARTUP_PROBE_KEY = "startupProbe";
const STARTUP_PROBE_ALARM = "dashboard-tabs-startup-probe";
const STARTUP_PROBE_DELAY_MINUTES = 2500 / 60000;
const REQUIRED_STABLE_PROBES = 2;
const LOG = "[dashboard-tabs]";

/** Reads the generated group/tab manifest bundled with the extension. */
async function loadConfig() {
  const response = await fetch(browser.runtime.getURL(CONFIG_PATH));
  if (!response.ok) {
    throw new Error(`cannot read ${CONFIG_PATH}: HTTP ${response.status}`);
  }
  return response.json();
}

/** Returns a stable identity for a Grafana dashboard URL, ignoring its slug. */
function dashboardKey(url) {
  if (typeof url !== "string") {
    return null;
  }
  try {
    const parsed = new URL(url);
    const match = parsed.pathname.match(/^\/d\/([^/?#]+)/);
    return match ? `${parsed.origin}/d/${match[1]}` : null;
  } catch {
    return null;
  }
}

/** Validates the generated config before it can drive browser mutations. */
function validateConfig(config) {
  if (!config || !Array.isArray(config.groups)) {
    throw new Error("config must contain a groups array");
  }

  const ids = new Set();
  for (const spec of config.groups) {
    if (
      !spec ||
      typeof spec.id !== "string" ||
      typeof spec.title !== "string" ||
      typeof spec.color !== "string" ||
      !Array.isArray(spec.tabs)
    ) {
      throw new Error("each group must define id, title, color, and tabs");
    }
    if (ids.has(spec.id)) {
      throw new Error(`duplicate group id ${spec.id}`);
    }
    ids.add(spec.id);
    for (const tab of spec.tabs) {
      if (
        !tab ||
        typeof tab.title !== "string" ||
        typeof tab.url !== "string" ||
        dashboardKey(tab.url) === null
      ) {
        throw new Error(`group ${spec.id} contains an invalid dashboard tab`);
      }
    }
  }
  return config;
}

function configuredTabs(spec) {
  return spec.tabs;
}

function configuredKeys(spec) {
  return new Set(configuredTabs(spec).map((tab) => dashboardKey(tab.url)));
}

async function loadManagedState() {
  try {
    const result = await browser.storage.local.get(STATE_KEY);
    const state = result?.[STATE_KEY];
    return state && typeof state === "object" && !Array.isArray(state) ? state : {};
  } catch (error) {
    console.error(`${LOG} managed state unreadable:`, error);
    return {};
  }
}

async function saveManagedState(state) {
  try {
    await browser.storage.local.set({ [STATE_KEY]: state });
  } catch (error) {
    // URL matching still permits recovery if storage is temporarily unavailable.
    console.error(`${LOG} managed state not saved:`, error);
  }
}

async function readTabMarker(tabId) {
  try {
    return await browser.sessions.getTabValue(tabId, TAB_MARKER_KEY);
  } catch {
    // The URL fallback still recognizes tabs created by older versions.
    return null;
  }
}

/**
 * Captures restore-relevant state without depending on browser-assigned IDs.
 * Group IDs and tab IDs can change during session restore, so only group
 * metadata, membership, dashboard identities, and counts are included.
 */
async function browserStateSignature() {
  const [groups, tabs] = await Promise.all([
    browser.tabGroups.query({}),
    browser.tabs.query({}),
  ]);
  const groupedKeys = new Map(groups.map((group) => [group.id, []]));
  let ungroupedTabs = 0;
  for (const tab of tabs) {
    if (!groupedKeys.has(tab.groupId)) {
      ungroupedTabs += 1;
      continue;
    }
    groupedKeys.get(tab.groupId).push(dashboardKey(tab.url) ?? "unavailable");
  }
  const groupState = groups
    .map((group) => ({
      title: group.title ?? "",
      color: group.color ?? "",
      collapsed: Boolean(group.collapsed),
      dashboardKeys: groupedKeys.get(group.id).sort(),
    }))
    .sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)));
  return JSON.stringify({ groupState, ungroupedTabs, totalTabs: tabs.length });
}

async function scheduleStartupProbe() {
  try {
    await browser.alarms.create(STARTUP_PROBE_ALARM, {
      delayInMinutes: STARTUP_PROBE_DELAY_MINUTES,
    });
  } catch (error) {
    console.error(`${LOG} startup probe alarm failed:`, error);
  }
}

async function clearStartupProbeState() {
  try {
    await browser.storage.local.remove(STARTUP_PROBE_KEY);
  } catch (error) {
    console.error(`${LOG} startup probe state not cleared:`, error);
  }
}

async function runStartupProbe() {
  let signature;
  try {
    signature = await browserStateSignature();
  } catch (error) {
    console.error(`${LOG} startup probe failed:`, error);
    await scheduleStartupProbe();
    return;
  }

  let previous;
  try {
    const result = await browser.storage.local.get(STARTUP_PROBE_KEY);
    previous = result?.[STARTUP_PROBE_KEY];
  } catch (error) {
    console.error(`${LOG} startup probe state unreadable:`, error);
  }
  const previousCount =
    previous && Number.isInteger(previous.stableProbes) ? previous.stableProbes : 0;
  const stableProbes =
    previous && previous.signature === signature ? previousCount + 1 : 1;
  try {
    await browser.storage.local.set({
      [STARTUP_PROBE_KEY]: { signature, stableProbes },
    });
  } catch (error) {
    console.error(`${LOG} startup probe state not saved:`, error);
  }

  if (stableProbes < REQUIRED_STABLE_PROBES) {
    await scheduleStartupProbe();
    return;
  }

  await clearStartupProbeState();
  void scheduleRun("startup");
}

async function initializeStartupProbe() {
  // Probe counts from an earlier browser session must not count toward this
  // restore. Alarms themselves are session-scoped, but storage is persistent.
  await clearStartupProbeState();
  await scheduleStartupProbe();
}

/** Finds a group owned by this extension, including groups restored with new IDs. */
async function findManagedGroup(spec, state) {
  const record = state[spec.id];
  const knownKeys = new Set(configuredKeys(spec));
  if (record && Array.isArray(record.dashboardKeys)) {
    for (const key of record.dashboardKeys) {
      if (typeof key === "string") {
        knownKeys.add(key);
      }
    }
  }
  if (knownKeys.size === 0) {
    return null;
  }

  const titles = new Set([spec.title]);
  if (record && typeof record.title === "string") {
    titles.add(record.title);
  }

  const groups = await browser.tabGroups.query({});
  const candidates = [];
  for (const group of groups) {
    const tabs = await browser.tabs.query({ groupId: group.id });
    const inspectedTabs = await Promise.all(
      tabs.map(async (tab) => ({ ...tab, marker: await readTabMarker(tab.id) })),
    );
    const markerMatches = inspectedTabs.filter(
      (tab) => tab.marker?.groupId === spec.id,
    ).length;
    const urlMatches = inspectedTabs.filter((tab) => {
      const markerKey =
        tab.marker?.groupId === spec.id ? tab.marker.dashboardKey : null;
      return knownKeys.has(dashboardKey(tab.url) ?? markerKey);
    }).length;
    const titleMatches = titles.has(group.title);
    if (markerMatches > 0 || (titleMatches && urlMatches > 0)) {
      candidates.push({
        group,
        tabs: inspectedTabs,
        matches: markerMatches * 1000 + urlMatches,
      });
    }
  }
  candidates.sort((left, right) => right.matches - left.matches || left.group.id - right.group.id);
  return candidates[0] ?? null;
}

async function removeTabs(tabIds) {
  if (tabIds.length === 0) {
    return;
  }
  try {
    await browser.tabs.remove(tabIds);
  } catch (error) {
    // A user or session restore may have closed one of the tabs already.
    console.error(`${LOG} could not clean up tabs:`, error);
  }
}

async function createDiscardedTabs(tabs) {
  const tabIds = [];
  for (const dashboard of tabs) {
    try {
      const tab = await browser.tabs.create({
        url: dashboard.url,
        title: dashboard.title,
        discarded: true,
        active: false,
      });
      if (typeof tab.id === "number") {
        tabIds.push(tab.id);
        try {
          await browser.sessions.setTabValue(tab.id, TAB_MARKER_KEY, {
            groupId: dashboard.ownerId,
            dashboardKey: dashboardKey(dashboard.url),
          });
        } catch (error) {
          // URL matching remains available if the sessions API is unavailable.
          console.error(`${LOG} could not mark ${dashboard.url}:`, error);
        }
      }
    } catch (error) {
      // One bad URL must not cost the whole group.
      console.error(`${LOG} could not open ${dashboard.url}:`, error);
    }
  }
  return tabIds;
}

async function updateManagedRecord(state, spec) {
  state[spec.id] = {
    title: spec.title,
    dashboardKeys: [...configuredKeys(spec)],
  };
  await saveManagedState(state);
}

async function reconcileGroup(spec, existing, state) {
  const expected = configuredKeys(spec);
  const previous = state[spec.id];
  const previouslyManaged = new Set(
    previous && Array.isArray(previous.dashboardKeys)
      ? previous.dashboardKeys.filter((key) => typeof key === "string")
      : [],
  );
  const managedKeys = new Set([...expected, ...previouslyManaged]);
  const seen = new Set();
  const staleIds = [];
  for (const tab of existing.tabs) {
    const markerKey =
      tab.marker?.groupId === spec.id ? tab.marker.dashboardKey : null;
    const key = dashboardKey(tab.url) ?? markerKey;
    const markedForGroup = tab.marker?.groupId === spec.id;
    if (!markedForGroup && !managedKeys.has(key)) {
      continue;
    }
    if (!expected.has(key) || seen.has(key)) {
      staleIds.push(tab.id);
    } else {
      seen.add(key);
    }
  }

  const missing = configuredTabs(spec).filter((tab) => !seen.has(dashboardKey(tab.url)));
  const newTabIds = await createDiscardedTabs(
    missing.map((tab) => ({ ...tab, ownerId: spec.id })),
  );
  try {
    if (newTabIds.length > 0) {
      await browser.tabs.group({ groupId: existing.group.id, tabIds: newTabIds });
    }
    await browser.tabGroups.update(existing.group.id, {
      title: spec.title,
      color: spec.color,
      collapsed: true,
    });
  } catch (error) {
    await removeTabs(newTabIds);
    throw error;
  }

  await removeTabs(staleIds);
  await updateManagedRecord(state, spec);
  const changes = [];
  if (newTabIds.length > 0) {
    changes.push(`added ${newTabIds.length} tabs`);
  }
  if (staleIds.length > 0) {
    changes.push(`removed ${staleIds.length} stale tabs`);
  }
  return {
    status: changes.length > 0 ? changes.join(", ") : "already open",
    groupId: existing.group.id,
  };
}

async function openGroup(spec, state) {
  const existing = await findManagedGroup(spec, state);
  if (existing) {
    return reconcileGroup(spec, existing, state);
  }

  const tabIds = await createDiscardedTabs(
    configuredTabs(spec).map((tab) => ({ ...tab, ownerId: spec.id })),
  );
  if (tabIds.length === 0) {
    return { status: "no tabs opened", groupId: null };
  }

  let groupId;
  try {
    groupId = await browser.tabs.group({ tabIds });
    await browser.tabGroups.update(groupId, {
      title: spec.title,
      color: spec.color,
      collapsed: true,
    });
  } catch (error) {
    await removeTabs(tabIds);
    throw error;
  }
  await updateManagedRecord(state, spec);
  return { status: `opened ${tabIds.length} tabs`, groupId };
}

async function openAllGroups(reason) {
  let config;
  try {
    config = validateConfig(await loadConfig());
  } catch (error) {
    console.error(`${LOG} config unreadable:`, error);
    return;
  }

  const state = await loadManagedState();
  for (const spec of config.groups) {
    try {
      const result = await openGroup(spec, state);
      console.info(`${LOG} ${reason}: ${spec.title}: ${result.status}`);
    } catch (error) {
      console.error(`${LOG} ${reason}: ${spec.title} failed:`, error);
    }
  }
}

// Event-page invocations share one promise. This closes the check-then-create
// race between startup, the toolbar, and repeated toolbar clicks.
let inFlight = null;

function scheduleRun(reason) {
  if (inFlight) {
    return inFlight;
  }
  inFlight = openAllGroups(reason)
    .catch((error) => console.error(`${LOG} ${reason} failed:`, error))
    .finally(() => {
      inFlight = null;
    });
  return inFlight;
}

// onStartup can fire before session restore has finished rebuilding the
// previous window. Repeated one-shot alarms require two identical snapshots
// before reconciliation, and storage keeps the probe state if the event page
// is suspended between alarms. Firefox exposes no session-restore-complete
// event, so this is deliberately a stability check rather than a fixed claim.
browser.runtime.onStartup.addListener(() => {
  void initializeStartupProbe();
});

browser.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === STARTUP_PROBE_ALARM) {
    void runStartupProbe();
  }
});

// The toolbar button runs the same action on demand, and is how you test
// without restarting Firefox.
browser.action.onClicked.addListener(() => {
  void scheduleRun("toolbar");
});
