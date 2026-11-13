//---------------------------------------------------------------------------Handling Navigation Highlighting -----------------------------------------------//
//Wait for an element to exist in the Dom
function waitForElm(selector) {
	return new Promise(resolve => {
		if (document.querySelector(selector)) {
			return resolve(document.querySelector(selector));
		}

		const observer = new MutationObserver(mutations => {
			if (document.querySelector(selector)) {
				resolve(document.querySelector(selector));
				observer.disconnect();
			}
		});

		observer.observe(document.body, {
			childList: true,
			subtree: true
		});
	});
}




// Highlight the nav link whose path best matches the current URL. We match by
// longest-prefix on pathname (not exact href), so a deep page like
// /en/foods/spinach still lights up the "Foods" tab. `aria-current="page"` is
// set alongside the visual class for accessibility.
function highlightActiveLink(navSelector, activeClass) {
	waitForElm(navSelector).then((nav) => {
		if (!nav) return;
		var links = nav.querySelectorAll('a[href]');
		var currentPath;
		try {
			currentPath = new URL(liveSocket.currentLocation.href).pathname;
		} catch (e) {
			currentPath = window.location.pathname;
		}

		var best = null;
		var bestLen = -1;
		links.forEach(function(a) {
			a.classList.remove(activeClass);
			a.removeAttribute('aria-current');
			var path;
			try {
				path = new URL(a.href).pathname;
			} catch (e) {
				return;
			}
			// A link matches when its path is the current path or a prefix of it
			// at a segment boundary ("/" root is handled as exact only).
			var matches = path === '/' ? currentPath === '/' :
				(currentPath === path ||
					currentPath.startsWith(path.endsWith('/') ? path : path + '/'));
			if (matches && path.length > bestLen) {
				best = a;
				bestLen = path.length;
			}
		});

		if (best) {
			best.classList.add(activeClass);
			best.setAttribute('aria-current', 'page');
		}
	});
}

function fix_navigation_active() {
	highlightActiveLink('#nav_bar_mobile', 'current');
	highlightActiveLink('#nav_bar', 'active');
}
fix_navigation_active();
//-----------------------------------------------------------Handling Navigation Highlighting ----------    THE END------------------------------------------------------

export {fix_navigation_active}

