#!/usr/bin/env node

import compression from "compression";
import express from "express";
import helmet from "helmet";
import morgan from "morgan";
import path from "path";
import cluster from "cluster";
import os from "os";

import { createRequestHandler } from "expo-server/adapter/express";
import { spawn } from "child_process";
import { getDatabase, getDatabaseLocation } from "./server/db";

const cpus = os.cpus().length;

const port = Number.parseInt(process.env.BACKEND_LISTEN_PORT ?? "");
if (!port || Number.isNaN(port)) {
	throw new Error(
		"❌  Invalid configuration: the environment variable `BACKEND_LISTEN_PORT` is missing or not a valid number.",
	);
}

const hostname = process.env.BACKEND_LISTEN_HOSTNAME?.trim();
if (!hostname) {
	throw new Error(
		"❌  Invalid configuration: the environment variable `BACKEND_LISTEN_HOSTNAME` is not set or is empty.",
	);
}

if (!("DISABLE_CLUSTER" in process.env) && cluster.isPrimary) {
	// Create a worker for each CPU
	for (let i = 0; i < cpus; i++) {
		cluster.fork();
	}

	cluster.on("online", function (worker) {
		console.log("Worker " + worker.process.pid + " is online.");
	});

	cluster.on("exit", function (worker, _code, _signal) {
		console.log("worker " + worker.process.pid + " died. Restarting...");
		cluster.fork();
	});

	if ("LITESTREAM_URL" in process.env) {
		// TODO make the exit more robust
		console.log("Trying to start Litestream");
		getDatabase(); // ensure DB exists

		const ls = spawn(
			"litestream",
			["replicate", getDatabaseLocation(), process.env.LITESTREAM_URL!],
			{ stdio: "inherit" }, // forward output directly
		);

		// Exit the app if Litestream terminates with an error code
		ls.on("close", (code) => {
			if (code !== 0) {
				console.error(`Litestream exited with code ${code}. Shutting down.`);
				process.exit(code);
			}
		});

		console.log("Launched litestream");
	} else {
		console.warn("⚠️ Not replicating over Litestream, data may be lost");
	}
} else {
	const CLIENT_BUILD_DIR = path.join(__dirname, "client");
	const SERVER_BUILD_DIR = path.join(__dirname, "server");

	const app = express();

	app.use(compression());
	app.use(helmet());

	// http://expressjs.com/en/advanced/best-practice-security.html#at-a-minimum-disable-x-powered-by-header
	app.disable("x-powered-by");

	app.use(express.static(CLIENT_BUILD_DIR));

	app.use(morgan("tiny"));

	app.all(
		"/{*all}",
		createRequestHandler({
			build: SERVER_BUILD_DIR,
		}),
	);

	process.on("SIGINT", function () {
		console.log("\nGracefully shutting down from SIGINT (Ctrl-C)");
		// some other closing procedures go here
		process.exit(0);
	});

	app.listen(port, hostname, () => {
		console.log(`Express server listening on port ${hostname}:${port}`);
	});
}
