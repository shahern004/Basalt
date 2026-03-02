<script>
	import { onMount, tick, setContext } from 'svelte';
	import { config, user, theme, WEBUI_NAME } from '$lib/stores';
	import { goto } from '$app/navigation';
	import { Toaster, toast } from 'svelte-sonner';

	import { getBackendConfig } from '$lib/apis';
	import { getSessionUser } from '$lib/apis/auths';

	import '../app.css';
	import '../tailwind.css';
	import 'tippy.js/dist/tippy.css';
	import { WEBUI_BASE_URL } from '$lib/constants';
	import i18n from '$lib/i18n';

	setContext('i18n', i18n);

	let loaded = false;

	onMount(async () => {
		// Enforce the dark theme for the app
		theme.set('dark');

		// Check Backend Status
		const backendConfig = await getBackendConfig(localStorage.token);

		if (backendConfig) {
			// Save Backend Status to Store
			await config.set(backendConfig);

			await WEBUI_NAME.set(backendConfig.name);
			console.log(backendConfig);

			if ($config) {
				if (localStorage.token) {
					// Get Session User Info
					const sessionUser = await getSessionUser(localStorage.token).catch((error) => {
						// Disabling this since the login is seamless and the user does not
						// need to be aware of the state of the session
						// toast.error(error);
						return null;
					});

					if (sessionUser) {
						// Save Session User to Store
						await user.set(sessionUser);
					} else {
						// Redirect Invalid Session User to /auth Page
						localStorage.removeItem('token');
						await goto('/auth');
					}
				} else {
					await goto('/auth');
				}
			}
		} else {
			// Redirect to /error when Backend Not Detected
			await goto(`/error`);
		}

		await tick();
		
		// after the page has loaded, send an event to clear the refresh timeout
		// and remove the splash screen
		const splashScreenElement = document.getElementById('splash-screen');
		splashScreenElement?.dispatchEvent(new Event('clear-splash-screen-timeout'))
		splashScreenElement?.remove();
		
		loaded = true;
	});
</script>

<svelte:head>
	<title>{$WEBUI_NAME}</title>
	<link rel="icon" href="{WEBUI_BASE_URL}/static/favicon.png" />

	<link rel="stylesheet" type="text/css" href="/themes/rosepine.css" />
	<link rel="stylesheet" type="text/css" href="/themes/rosepine-dawn.css" />
</svelte:head>

{#if loaded}
	<slot />
{/if}

<Toaster richColors position="top-center" />
