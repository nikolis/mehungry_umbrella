import "phoenix_html"
import {
	Socket
} from "phoenix"
import {
	LiveSocket
} from "phoenix_live_view"
import jQuery from "jquery"
import select2 from "select2";
import "selectize";
import { fix_navigation_active } from './navigation.js';
import { Hooks } from './hooks.js'
import { Uploaders } from './uploaders.js'
import Alpine from 'alpinejs'

window.Alpine = Alpine
Alpine.start()

window.addEventListener("phx:js-exec", ({detail}) => {
  document.querySelectorAll(detail.to).forEach(el => {
      liveSocket.execJS(el, el.getAttribute(detail.attr))
  })
})

// Generic bridge for LiveView-driven GA4 custom events pushed via
// MehungryWeb.GoogleAnalytics.track/3. Consent Mode (set in head.html.heex)
// handles the pre-consent cookieless-ping downgrade automatically, so no
// consent check is needed here.
window.addEventListener("phx:ga_event", ({detail}) => {
  if (typeof gtag === "function" && detail && detail.name) {
    gtag('event', detail.name, detail.params || {})
  }
})

// GA's automatic page_view only fires once, on the very first script load —
// this app is a LiveView SPA, so subsequent in-app navigation needs a manual
// page_view per navigation. `send_page_view: false` is set in head.html.heex
// so this is the only page_view source (initial load included).
window.addEventListener("phx:page-loading-stop", (e) => {
  if (typeof gtag === "function" && (!e.detail || e.detail.kind !== "error")) {
    gtag('event', 'page_view', {
      page_location: window.location.href,
      page_path: window.location.pathname + window.location.search,
      page_title: document.title
    })
  }
})



var dirty_bit = document.getElementById('page_is_dirty');

function mark_page_dirty() {
	if (dirty_bit) {
		dirty_bit.value = '1';
	}
}

mark_page_dirty();


$(document).ready(function() {
	$(".nav-toggler").each(function(_, navToggler) {
		var target = $(navToggler).data("target");
		$(navToggler).on("click", function() {
			$(target).animate({
				height: "toggle",
			});
		});
	});
});


let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

//LiveSocket Creation 
let liveSocket = new LiveSocket("/live", Socket, {
	hooks: Hooks,
	uploaders: Uploaders,
  dom: {
    onBeforeElUpdated(from, to) {
    // Preserve Alpine component state
      if (from.__x) {
        // Prevent LiveView from removing Alpine-managed elements
        return false
      }    }
  },
	params: {
		_csrf_token: csrfToken,
    viewport: {
      width: window.screen.width,
      height: window.screen.height
    }
	}
})


//Use the liveSocket to create navigation bar highlighting using 
//naviagation modules functions 
var currentLocationProxy = new Proxy(liveSocket, {
	set: function(target, key, value) {
		if (key == "href") {
			fix_navigation_active()
		}
		target[key] = value;
		return true;
	}
});



currentLocationProxy.connect()

// connect if there are any LiveViews on the page
//liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = currentLocationProxy;
