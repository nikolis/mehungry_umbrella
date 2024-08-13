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
import { multiselect } from './select.js';




function toggleMenu() {
	console.log("toogle mennu")
}
 
window.addEventListener('load', function() {
	var modal = document.getElementById('modal');
	if (modal) {
		console.log(modal);
		modal.removeAttribute('style');
	}

 	//document.getElementById("modal").style.visibility = "visible";
	//modal.classList.remove("is-closing")
	//modal.classList.add("is-closed");
	//modal.classList.add("portfolio-modal");

});

$(".portfolio-modal").on("animationend", function(e) {
	if (e.originalEvent.animationName === 'modalFadeOut') {
		this.classList.remove("is-closing");
		this.classList.add("is-closed");
	}

});

$(".portfolio-modal").on("animationstart", function(e) {
	if (e.originalEvent.animationName === 'modalFadeOut') {
		//this.classList.remove("is-closing");
		//this.classList.add("is-closed");
	}

});



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
      if (from._x_dataStack) {
        window.Alpine.clone(from, to)
      }
    }
  },
	params: {
		_csrf_token: csrfToken
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
