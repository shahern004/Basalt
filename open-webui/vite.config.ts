import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';
import type { Plugin } from 'vite';
import type { OutputBundle, OutputChunk, OutputAsset, NormalizedOutputOptions } from 'rollup'
import path from "path";

function isOutputChunk(outputChunk: OutputAsset | OutputChunk ) {
	return (
		'code' in outputChunk
		&& 'map' in outputChunk
		&& 'sourcemapFileName' in outputChunk 
		&& 'preliminaryFileName' in outputChunk
	)
}

function useCredentials(): Plugin {
	// from: https://github.com/vitejs/vite/issues/6648#issuecomment-1982827778
	return {
		name: 'use-credentials',
		generateBundle(options: NormalizedOutputOptions, bundle: OutputBundle) {
			for (const url in bundle) {
				const chunk = bundle[url];

				if (isOutputChunk(chunk)) {
					const chunk_path = path.join(options.dir ? options.dir : "", url)

					// handles lazy loaded imports
					if (chunk.name === 'helper' && chunk.code.includes("crossOrigin")) {

						console.log("\n crossOrigin", chunk_path)
						chunk.code = chunk.code.replace(
							'crossOrigin=""',
							'crossOrigin="use-credentials"'
						);

					// handles svletekit injected modulepreload links
					} else if (chunk.name === 'index' && chunk.code.includes("modulepreload")) {
						
						console.log("\n modulepreload", chunk_path)
						chunk.code = chunk.code.replace(
							'<link rel="modulepreload"',
							'<link rel="modulepreload" crossorigin="use-credentials"'
						);
					}
				}
			}
		},
	};
}



export default defineConfig({
	plugins: [
		sveltekit(),
		useCredentials(),
	],
	define: {
		APP_VERSION: JSON.stringify(process.env.npm_package_version)
	},
	build: {
		rollupOptions: {
			output: {
				manualChunks(id) {
				if (id.startsWith('\u0000vite')) {
					return 'helper';
				}
				},
			},
		},
	},
});
