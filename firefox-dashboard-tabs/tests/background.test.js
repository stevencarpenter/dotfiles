"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const SOURCE = fs.readFileSync(path.join(__dirname, "..", "extension", "background.js"), "utf8");

function makeHarness(config) {
  let nextTabId = 1;
  let nextGroupId = 100;
  let currentConfig = config;
  const tabs = new Map();
  const tabMarkers = new Map();
  const groups = new Map();
  const managedState = {};
  const probeState = {};
  const listeners = { alarm: null, startup: null, toolbar: null };
  const alarms = [];
  let failNextGroup = false;
  let failNextUpdate = false;

  const browser = {
    runtime: {
      getURL: (name) => `moz-extension://test/${name}`,
      onStartup: { addListener: (listener) => (listeners.startup = listener) },
    },
    alarms: {
      create: async (name, info) => alarms.push({ name, info }),
      onAlarm: { addListener: (listener) => (listeners.alarm = listener) },
    },
    action: {
      onClicked: { addListener: (listener) => (listeners.toolbar = listener) },
    },
    storage: {
      local: {
        get: async (key) =>
          key === "startupProbe"
            ? { startupProbe: probeState }
            : { managedGroups: managedState },
        set: async (value) => {
          if (value.managedGroups) {
            Object.assign(managedState, value.managedGroups);
          }
          if (value.startupProbe) {
            Object.assign(probeState, value.startupProbe);
          }
        },
        remove: async (key) => {
          if (key === "startupProbe") {
            for (const property of Object.keys(probeState)) {
              delete probeState[property];
            }
          }
        },
      },
    },
    sessions: {
      setTabValue: async (tabId, key, value) => {
        tabMarkers.set(`${tabId}:${key}`, value);
      },
      getTabValue: async (tabId, key) => tabMarkers.get(`${tabId}:${key}`),
    },
    tabGroups: {
      query: async () => [...groups.values()].map((group) => ({ ...group })),
      update: async (id, changes) => {
        if (failNextUpdate) {
          failNextUpdate = false;
          throw new Error("simulated group update failure");
        }
        Object.assign(groups.get(id), changes);
      },
    },
    tabs: {
      create: async (properties) => {
        const tab = { id: nextTabId++, ...properties, groupId: -1 };
        tabs.set(tab.id, tab);
        return { ...tab };
      },
      query: async ({ groupId } = {}) =>
        [...tabs.values()]
          .filter((tab) => groupId === undefined || tab.groupId === groupId)
          .map((tab) => ({ ...tab })),
      group: async ({ tabIds, groupId }) => {
        if (failNextGroup) {
          failNextGroup = false;
          throw new Error("simulated grouping failure");
        }
        const ids = Array.isArray(tabIds) ? tabIds : [tabIds];
        const targetId = groupId ?? nextGroupId++;
        if (groupId === undefined) {
          groups.set(targetId, { id: targetId, title: undefined, color: undefined, collapsed: false });
        }
        for (const id of ids) {
          tabs.get(id).groupId = targetId;
        }
        return targetId;
      },
      remove: async (tabIds) => {
        const ids = Array.isArray(tabIds) ? tabIds : [tabIds];
        for (const id of ids) {
          const tab = tabs.get(id);
          if (!tab) {
            continue;
          }
          const groupId = tab.groupId;
          tabs.delete(id);
          tabMarkers.delete(`${id}:dashboard-tabs-owner`);
          if (groupId !== -1 && ![...tabs.values()].some((candidate) => candidate.groupId === groupId)) {
            groups.delete(groupId);
          }
        }
      },
    },
  };

  const context = {
    browser,
    URL,
    fetch: async () => ({ ok: true, json: async () => currentConfig }),
    console: { error() {}, info() {} },
  };
  vm.runInNewContext(
    `${SOURCE}\nthis.__dashboardTabsTest = { dashboardKey, scheduleRun };`,
    context,
    { filename: "background.js" },
  );

  return {
    run: (reason = "test") => context.__dashboardTabsTest.scheduleRun(reason),
    setConfig: (value) => (currentConfig = value),
    setNextGroupFailure: () => (failNextGroup = true),
    setNextUpdateFailure: () => (failNextUpdate = true),
    setTabUrl: (id, url) => (tabs.get(id).url = url),
    setGroupTitle: (id, title) => (groups.get(id).title = title),
    addForeignGroup: (title, url) => {
      const groupId = nextGroupId++;
      groups.set(groupId, { id: groupId, title, color: "blue", collapsed: false });
      const id = nextTabId++;
      tabs.set(id, { id, url, title: "foreign", groupId });
    },
    snapshot: () => ({
      tabs: [...tabs.values()].map((tab) => ({ ...tab })),
      groups: [...groups.values()].map((group) => ({ ...group })),
      alarms: [...alarms],
    }),
    listeners,
  };
}

function config(tabs) {
  return { groups: [{ id: "test", title: "Test", color: "purple", tabs }] };
}

function dashboard(uid, title = uid) {
  return { uid, title, url: `http://localhost:3030/d/${uid}` };
}

test("serializes overlapping runs so concurrent clicks create one group", async () => {
  const harness = makeHarness(config([dashboard("one"), dashboard("two")]));

  await Promise.all([harness.run(), harness.run()]);

  assert.equal(harness.snapshot().groups.length, 1);
  assert.equal(harness.snapshot().tabs.length, 2);
});

test("reconciles canonical Grafana URLs, additions, and stale tabs", async () => {
  const harness = makeHarness(config([dashboard("one"), dashboard("two")]));
  await harness.run();
  const first = harness.snapshot();
  harness.setTabUrl(first.tabs[0].id, "http://localhost:3030/d/one/renamed-dashboard");
  harness.setConfig(config([dashboard("one"), dashboard("three")]));

  await harness.run();

  const result = harness.snapshot();
  assert.equal(result.groups.length, 1);
  assert.deepEqual(
    result.tabs.map((tab) => tab.url).sort(),
    [
      "http://localhost:3030/d/one/renamed-dashboard",
      "http://localhost:3030/d/three",
    ],
  );
});

test("uses private tab markers when a dashboard redirects or is renamed", async () => {
  const harness = makeHarness(config([dashboard("one")]));
  await harness.run();
  const first = harness.snapshot();
  harness.setGroupTitle(first.groups[0].id, "User renamed this");
  harness.setTabUrl(first.tabs[0].id, "https://grafana.snugmarina.org/login");

  await harness.run();

  const result = harness.snapshot();
  assert.equal(result.groups.length, 1);
  assert.equal(result.groups[0].title, "Test");
  assert.equal(result.tabs.length, 1);
});

test("does not claim an unrelated same-titled group", async () => {
  const harness = makeHarness(config([dashboard("one")]));
  harness.addForeignGroup("Test", "http://example.com/other");

  await harness.run();

  const result = harness.snapshot();
  assert.equal(result.groups.length, 2);
  assert.equal(result.tabs.filter((tab) => tab.groupId !== -1).length, 2);
});

test("removes created tabs when grouping fails", async () => {
  const harness = makeHarness(config([dashboard("one")]));
  harness.setNextGroupFailure();

  await harness.run();

  assert.deepEqual(harness.snapshot().tabs, []);
  assert.deepEqual(harness.snapshot().groups, []);
});

test("removes newly created tabs when an existing-group update fails", async () => {
  const harness = makeHarness(config([dashboard("one")]));
  await harness.run();
  harness.setConfig(config([dashboard("one"), dashboard("two")]));
  harness.setNextUpdateFailure();

  await harness.run();
  assert.equal(harness.snapshot().tabs.length, 1);

  await harness.run();
  assert.equal(harness.snapshot().tabs.length, 2);
});

test("uses an alarm for delayed startup work", async () => {
  const harness = makeHarness(config([dashboard("one")]));

  harness.listeners.startup();
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(harness.snapshot().alarms.length, 1);
  assert.equal(harness.snapshot().alarms[0].name, "dashboard-tabs-startup-probe");
  assert.equal(harness.snapshot().alarms[0].info.delayInMinutes, 2500 / 60000);

  await harness.listeners.alarm({ name: "dashboard-tabs-startup-probe" });
  await new Promise((resolve) => setImmediate(resolve));
  await harness.listeners.alarm({ name: "dashboard-tabs-startup-probe" });
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(harness.snapshot().groups.length, 1);
});
