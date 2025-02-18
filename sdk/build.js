import esbuild from 'esbuild';
import dtsPlugin from 'esbuild-plugin-d.ts';
import path from 'path';

// SDK build configurations (unchanged)
const sharedConfig = {
	entryPoints: ['src/index.ts'],
	bundle: true,
	sourcemap: true,
	minify: true,
	inject: [path.resolve('node_modules/process/browser.js')],
	define: {
		'process.env.NODE_ENV': JSON.stringify('production'),
	},
};

const sdkBuildConfigs = [
	// Node.js (CJS)
	{
		...sharedConfig,
		outfile: 'dist/index.cjs.js',
		platform: 'node',
		format: 'cjs',
		plugins: [dtsPlugin({ outDir: 'dist/types' })],
	},
	// Browser (ESM)
	{
		...sharedConfig,
		outfile: 'dist/index.esm.js',
		platform: 'browser',
		format: 'esm',
		plugins: [dtsPlugin({ outDir: 'dist/types' })],
	},
];

const cliBuildConfig = {
	entryPoints: ['cli/index.ts'],
	bundle: true,
	sourcemap: true,
	minify: true,
	outfile: 'bin/index.cjs',
	platform: 'node',
	format: 'cjs',
	banner: { js: "#!/usr/bin/env node" },
	external: ['canvas'], // Exclude canvas from bundling
	loader: { '.node': 'file' } // Optionally configure .node loader if needed
};

async function build() {
	try {
		const configs = [...sdkBuildConfigs, cliBuildConfig];
		await Promise.all(configs.map(async (config, index) => {
			console.log(`Building configuration ${index + 1}:`, config.outfile);
			await esbuild.build(config);
			console.log(`Finished building configuration ${index + 1}:`, config.outfile);
		}));
		console.log('Build complete!');
	} catch (error) {
		console.error('Build failed:', error);
		process.exit(1);
	}
}

build();