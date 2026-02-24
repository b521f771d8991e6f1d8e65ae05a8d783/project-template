export async function GET(_request: Request, {}: Record<string, string>) {
	return Response.json({ status: "👌" });
}
