// omlx-discovery: register the "omlx" provider from the oMLX server's live
// /v1/models instead of hand-maintaining model IDs in models.json.
//
// Layering: models.json keeps a static fallback list (last-known-good IDs,
// shown when the server is down at startup); this extension REPLACES that
// list whenever the server answers. Refresh cycles re-fetch and pi caches
// the catalog in models-store.json for offline restarts.
//
// ponytail: metadata is guessed (reasoning=false, zero cost,
// maxTokens=contextWindow); pin per-model overrides in models.json when a
// model misbehaves.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const BASE_URL = process.env.OMLX_BASE_URL ?? "http://localhost:42069/v1";
const API_KEY = process.env.OMLX_API_KEY ?? "omlx";
// Not chat-completable: embedding/rerank/document models.
const NON_CHAT = /embed|rerank|markitdown|whisper|tts/i;

type DiscoveredModel = {
	id: string;
	name: string;
	reasoning: boolean;
	input: ("text" | "image")[];
	cost: { input: number; output: number; cacheRead: number; cacheWrite: number };
	contextWindow: number;
	maxTokens: number;
};

async function fetchOmlxModels(): Promise<DiscoveredModel[]> {
	const res = await fetch(`${BASE_URL}/models`, {
		headers: { Authorization: `Bearer ${API_KEY}` },
		signal: AbortSignal.timeout(3000),
	});
	if (!res.ok) throw new Error(`omlx /v1/models: HTTP ${res.status}`);
	const body = (await res.json()) as {
		data?: { id?: string; max_model_len?: number | null }[];
	};
	return (body.data ?? [])
		.filter((m) => m.id && !NON_CHAT.test(m.id))
		.map((m) => ({
			id: m.id as string,
			name: m.id as string,
			reasoning: false,
			input: ["text"],
			cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
			contextWindow: m.max_model_len ?? 128000,
			maxTokens: m.max_model_len ?? 16384,
		}));
}

export default async function (pi: ExtensionAPI) {
	// Await inside the factory so pi waits for discovery before startup
	// finishes (docs: register discovered models in the factory, not
	// session_start). On failure register nothing so the static models.json
	// fallback list stays visible.
	try {
		const models = await fetchOmlxModels();
		if (!models.length) return;
		pi.registerProvider("omlx", {
			name: "oMLX (local)",
			baseUrl: BASE_URL,
			api: "openai-completions",
			apiKey: API_KEY,
			models,
			// Re-fetch on pi's model-catalog refresh cycles.
			refreshModels: async () => fetchOmlxModels(),
		});
	} catch {
		// Server unreachable: models.json fallback applies, nothing to do.
	}
}
