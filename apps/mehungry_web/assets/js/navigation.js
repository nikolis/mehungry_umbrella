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




function fix_navigation_active() {

	waitForElm('#nav_bar').then((elm) => {
		var nav = document.getElementsByTagName("nav")[0];
		if (nav) {
			nav.classList.add('active');
			var childNodes = nav.childNodes;
			childNodes.forEach(function(arg1, arg2) {
				if (arg2 == 1 || arg2 == 5) {
					var leaves1 = arg1.childNodes;
					leaves1.forEach(function(arg3, arg4) {
						if (arg3.classList) {
							if (arg3.href == liveSocket.currentLocation.href) {
								arg3.classList.add("active");
							}
						}
					});
				}
			});
		}
	});
}
fix_navigation_active();
//-----------------------------------------------------------Handling Navigation Highlighting ----------    THE END------------------------------------------------------

export {fix_navigation_active}

