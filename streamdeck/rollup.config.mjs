import commonjs from "@rollup/plugin-commonjs";
import nodeResolve from "@rollup/plugin-node-resolve";
import terser from "@rollup/plugin-terser";
import typescript from "@rollup/plugin-typescript";
import fs from "node:fs";

const sdPlugin = "cam.lenslink.streamdeck.sdPlugin";

export default {
	input: "src/plugin.ts",
	output: { file: `${sdPlugin}/bin/plugin.js` },
	plugins: [
		{
			name: "property-inspector-locales",
			buildStart() {
				const locales = {};
				for (const file of fs.readdirSync(sdPlugin).filter((f) => /^[a-z]{2}(_[A-Z]{2})?\.json$/.test(f))) {
					this.addWatchFile(`${sdPlugin}/${file}`);
					locales[file.slice(0, -5)] = JSON.parse(fs.readFileSync(`${sdPlugin}/${file}`, "utf8")).Localization;
				}
				fs.writeFileSync(`${sdPlugin}/ui/locales.js`, `SDPIComponents.i18n.locales = ${JSON.stringify(locales)};\n`);
			}
		},
		typescript(),
		nodeResolve({ browser: false, exportConditions: ["node"], preferBuiltins: true }),
		commonjs(),
		!process.env.ROLLUP_WATCH && terser(),
		{
			name: "emit-module-package-file",
			generateBundle() {
				this.emitFile({ fileName: "package.json", source: `{ "type": "module" }`, type: "asset" });
			}
		}
	]
};
