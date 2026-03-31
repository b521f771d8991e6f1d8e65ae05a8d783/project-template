import { app, BrowserWindow } from "electron";
import net from "net";
import path from "path";

const HOST = "127.0.0.1";

function findFreePort(start: number): Promise<number> {
	return new Promise((resolve) => {
		const server = net.createServer();
		server.listen(start, HOST, () => {
			const addr = server.address() as net.AddressInfo;
			server.close(() => resolve(addr.port));
		});
		server.on("error", () => resolve(findFreePort(start + 1)));
	});
}

function waitForServer(port: number, retries = 50): Promise<void> {
	return new Promise((resolve, reject) => {
		const attempt = () => {
			const socket = net.connect(port, HOST);
			socket.on("connect", () => {
				socket.destroy();
				resolve();
			});
			socket.on("error", () => {
				if (--retries <= 0) {
					reject(new Error("Express server did not start in time"));
					return;
				}
				setTimeout(attempt, 100);
			});
		};
		attempt();
	});
}

app
	.whenReady()
	.then(async () => {
		const port = await findFreePort(8081);

		// Set env vars before loading main.js so its top-level validation passes.
		process.env.BACKEND_LISTEN_PORT = String(port);
		process.env.BACKEND_LISTEN_HOSTNAME = HOST;
		// Disable clustering — Electron's main process is already a single Node process.
		process.env.DISABLE_CLUSTER = "1";

		// Dynamically require the Express server so env vars are in place first.
		// The path resolves to main.js sitting next to this file in the output.
		// eslint-disable-next-line @typescript-eslint/no-require-imports
		require(path.join(__dirname, "main.js"));

		await waitForServer(port);

		const win = new BrowserWindow({
			width: 1200,
			height: 800,
			webPreferences: {
				nodeIntegration: false,
				contextIsolation: true,
			},
		});

		await win.loadURL(`http://${HOST}:${port}/internal`);

		app.on("window-all-closed", () => {
			// On macOS apps conventionally stay open until Cmd+Q.
			if (process.platform !== "darwin") app.quit();
		});
	})
	.catch((err: unknown) => {
		console.error("Electron startup failed:", err);
		app.quit();
	});
