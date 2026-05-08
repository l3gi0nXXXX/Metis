export default async function register(api: any) {
  api.registerTool({ name: "real.fixture.source" }, async () => ({ ok: true }));
}
