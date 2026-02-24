import sqlite from "node:sqlite";
const path = require("path");

export function getDatabaseLocation() {
	return path.resolve(process.cwd(), "data.db");
}

export function getDatabase() {
	const db = new sqlite.DatabaseSync(getDatabaseLocation());
	db.exec("PRAGMA journal_mode = WAL;");
	db.exec("PRAGMA synchronous = NORMAL;");
	return db;
}
