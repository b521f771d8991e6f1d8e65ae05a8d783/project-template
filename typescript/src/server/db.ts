import sqlite from "node:sqlite";
import fs from "node:fs";
import path from "node:path";

export function getDatabaseLocation() {
	return path.resolve(process.cwd(), "data.db");
}

export function getDatabase() {
	const dbPath = getDatabaseLocation();
	const isNew = !fs.existsSync(dbPath);
	const db = new sqlite.DatabaseSync(dbPath);
	db.exec("PRAGMA journal_mode = WAL;");
	db.exec("PRAGMA synchronous = NORMAL;");
	db.exec("PRAGMA foreign_keys = ON;");

	if (isNew) {
		const schemaPath = path.resolve(process.cwd(), "database.sql");
		const schema = fs.readFileSync(schemaPath, "utf-8");
		db.exec(schema);
	}

	return db;
}
