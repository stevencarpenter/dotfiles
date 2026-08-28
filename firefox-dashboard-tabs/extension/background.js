"use strict";

// Opens each configured dashboard set as its own collapsed tab group.
//
// Tabs are created discarded, so a group costs nothing at startup and a
// dashboard whose backend is down (hippo's Grafana only runs when the OTel
// stack is up) shows a placeholder rather than a connection error. Firefox
// only permits a caller-supplied tab title when the tab is discarded, which
// is why every tab carries its dashboard name from dashboards.json.

const CONFIG_PATH = "dashboards.json";
const LOG = "[dashboard-tabs]";

/** Reads the generated group/tab manifest bundled with the extension. */
async function loadConfig() {
  const response = await fetch(browser.runtime.getURL(CONFIG_PATH));
  if (!response.ok) {
    throw new Error(`cannot read ${CONFIG_PATH}: HTTP ${response.status}`);
  }
  return response.json();
}

// tabGroups.query() treats `title` as a pattern in some engines, so match
// exactly here instead. This is what makes a re-run idempotent: a group
// restored by session restore must not be duplicated.
async function findGroupByTitle(title) {
  const groups = await browser.tabGroups.query({});
  return groups.find((group) => group.title === title) ?? null;
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
      tabIds.push(tab.id);
    } catch (error) {
      // One bad URL must not cost the whole group.
      console.error(`${LOG} could not open ${dashboard.url}:`, error);
    }
  }
  return tabIds;
}

async function openGroup(spec) {
  const existing = await findGroupByTitle(spec.title);
  if (existing) {
    return { status: "already open", groupId: existing.id };
  }

  const tabIds = await createDiscardedTabs(spec.tabs ?? []);
  if (tabIds.length === 0) {
    return { status: "no tabs opened", groupId: null };
  }

  const groupId = await browser.tabs.group({ tabIds });
  await browser.tabGroups.update(groupId, {
    title: spec.title,
    color: spec.color,
    collapsed: true,
  });
  return { status: `opened ${tabIds.length} tabs`, groupId };
}

async function openAllGroups(reason) {
  let config;
  try {
    config = await loadConfig();
  } catch (error) {
    console.error(`${LOG} config unreadable:`, error);
    return;
  }

  for (const spec of config.groups ?? []) {
    try {
      const result = await openGroup(spec);
      console.info(`${LOG} ${reason}: ${spec.title}: ${result.status}`);
    } catch (error) {
      console.error(`${LOG} ${reason}: ${spec.title} failed:`, error);
    }
  }
}

// onStartup can fire before session restore has finished rebuilding the
// previous window, including any group this extension opened last time. Acting
// immediately would find no matching group and duplicate every tab, so the
// startup path waits for restore to settle before checking.
const SETTLE_MS = 2500;

const settle = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

browser.runtime.onStartup.addListener(async () => {
  await settle(SETTLE_MS);
  await openAllGroups("startup");
});

// The toolbar button runs the same action on demand, and is how you test
// without restarting Firefox.
browser.action.onClicked.addListener(() => openAllGroups("toolbar"));
