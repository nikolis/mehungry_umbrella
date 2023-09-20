$('#lab1').click(function() {
	var idd = $('#lab1').attr('for')
	$("#" + idd).trigger("click")
});


var pushState = history.pushState;
history.pushState = function() {
	pushState.apply(history, arguments);
	//    console.log(window.liveSocket.currentLocation.pathname)
};


history.replaceState = function() {
	replaceState.apply(history, arguments);
	console.log("replace_state")
};


history.go = function() {
	go.apply(history, arguments);
	console.log("go_state")
};


addEventListener("load", (event) => {
	console.log("loaded")
});
window.addEventListener("hashchange", (event) => {
	console.log("weeeeeeee")
});

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


Hooks.MenuToggleHook = {
	mounted() {
		var drop_down_open = false;
		$('#menu_utils_toggle').on("click", function() {
			console.log("click");
			if (!drop_down_open) {
				$('#menu_items_list').addClass("drop_down_open");
				$('#menu_items_list').removeClass("drop_down");
				drop_down_open = true;
			} else {
				$('#menu_items_list').removeClass("drop_down_open");
				$('#menu_items_list').addClass("drop_down");
				drop_down_open = false;
			}
		});
	}
}
