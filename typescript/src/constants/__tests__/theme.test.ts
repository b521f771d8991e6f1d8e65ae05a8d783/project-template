import { Colors } from "@/constants/theme";
import { describe, expect, test } from "@jest/globals";

describe("theme-tests", () => {
	test("is-working", () => {
		expect(Colors.light.background).toStrictEqual("#fff");
	});
});
