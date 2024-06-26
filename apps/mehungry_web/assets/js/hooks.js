import "selectize";

let Hooks = {}

Hooks.MyModalHook = {

	mounted() {
		console.log("My modal hook");
		const closeModal = document.getElementById("button-close-modal");
		const modal = document.getElementById("my_modal");
		var patch = modal.getAttribute('patch')
		modal.addEventListener("close", () => {
			this.pushEvent("close-modal", {to: patch});

		});
		modal.showModal();
		console.log("Mount load end");
		closeModal.addEventListener('click', () => {
			modal.close();
		});
	}
}

Hooks.Select2Multi = {

	initSelect2(element, hook, hiddenIdFull, selects, index, hook_layer_id, select_layer_id, placeholder) {
		let hook2 = this;
		let $select = selects[0]
		console.log(hook_layer_id)
		let id = '#' + select_layer_id ;
		console.log(id)
		//var s = document.getElementById(element.id);
		$select.value = $(hiddenIdFull).val();
	        	
		$('#' + element.id).val($(hiddenIdFull).val())
  	

		selects.select2().on("change", (e) =>
			hook.item_selected($select, e, hiddenIdFull)
		)
		$(id).select2({
        	    dropdownParent: $('#'+hook_layer_id),
		    closeOnSelect: true,
		    debug: true,
		    placeholder: placeholder,

    		});

		return element
	},

	item_selected(element, event, hiddenIdFull) {
		if ($(element).val().length === 0) {
			//$(hiddenIdFull).find('option').attr("selected",false) ;
			//$(hiddenIdFull).prop('selectedIndex', -1)
		} else {
			$(hiddenIdFull).val($(element).val()).change()
		}
		element.dispatchEvent(new Event("input", {
			bubbles: true,
			cancelable: true
		}))
		return event;
	},

	mounted() {

		let hiddenId = this.el.getAttribute("data-hidden-id")
		let index = this.el.getAttribute("data-index")
		let hook_layer_id = this.el.getAttribute("id")
		let select_layer_id = this.el.getAttribute("data-select-layer-id")
		let placeholder = this.el.getAttribute("placeholder")
		let hiddenIdFull = '#' + hiddenId
		let $selects = jQuery(this.el).find("select");
		let $select = $selects[0];
		
		this.initSelect2(this.el, this, hiddenIdFull, $selects, index, hook_layer_id, select_layer_id, placeholder)
	}
}



//The clickable area falls within  the drop zone which creates problems to the click to upload functionality which is why This triggered is used to propagate the click to the apropriate ellement  
Hooks.ImageSelect = {
	mounted() {
		$('#lab1').click(function() {
			var idd = $('#lab1').attr('for')
			$("#" + idd).trigger("click")
		});
	}
}


function swap_ingredients() {
	if ( document.getElementById("flip_card").classList.contains('flip_card_turned') ) {
  		document.getElementById("flip_card").classList.remove('flip_card_turned');
	} else {
  		document.getElementById("flip_card").classList.add('flip_card_turned');
	}

}
Hooks.SwapElement = {
	mounted() {
		document.getElementById("button_swap_ingredients").onclick = function() {swap_ingredients()};
	}
}

Hooks.MenuToggleHook = {
	mounted() {
		var drop_down_open = false;
		$('#menu_utils_toggle').on("click", function() {
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


let scrollAt = () => {
	let scrollTop = document.documentElement.scrollTop || document.body.scrollTop
	let scrollHeight = document.documentElement.scrollHeight || document.body.scrollHeight
	let clientHeight = document.documentElement.clientHeight

	return scrollTop / (scrollHeight - clientHeight) * 100
}



Hooks.InfiniteScroll = {
	page() {
		return this.el.dataset.page
	},
	mounted() {
		this.pending = this.page()
		window.addEventListener("scroll", e => {
			if (this.pending == this.page() && scrollAt() > 84) {
				this.pending = Number(this.page()) + Number(1)
				this.pushEvent("load-more", {})
			}
		})
	},
	reconnected() {
		this.pending = this.page()
	},
	updated() {
		this.pending = this.page()
	}
}

Hooks.AccordionHook = {
	page() {
	},
	mounted() {
		const accordion = document.querySelector(".accordion");

accordion.addEventListener("click", (e) => {
  const activePanel = e.target.closest(".accordion-panel");
  if (!activePanel) return;
  toggleAccordion(activePanel);
});

function toggleAccordion(panelToActivate) {
  const activeButton = panelToActivate.querySelector("button");
  const activePanel = panelToActivate.querySelector(".accordion-content");
  const activePanelIsOpened = activeButton.getAttribute("aria-expanded");

  if (activePanelIsOpened === "true") {
    panelToActivate
      .querySelector("button")
      .setAttribute("aria-expanded", false);

    panelToActivate
      .querySelector(".accordion-content")
      .setAttribute("aria-hidden", true);
  } else {
    panelToActivate.querySelector("button").setAttribute("aria-expanded", true);

    panelToActivate
      .querySelector(".accordion-content")
      .setAttribute("aria-hidden", false);
  }
}

	},
	reconnected() {
	},
	updated() {
	}
}


Hooks.GoogleLoginHook = {
	mounted() {
		console.log("Mounter")
	}

}

Hooks.Select2 = {

	initSelect2(element, hook, hiddenIdFull, selects) {
		let hook2 = this;
		let $select = selects[0]

		selects.select2().on("change", (e) =>
			hook.item_selected($select, e, hiddenIdFull)
		)

		return element
	},

	item_selected(element, event, hiddenIdFull) {
		$(hiddenIdFull).val($(element).val()).change()
		element.dispatchEvent(new Event("input", {
			bubbles: true,
			cancelable: true
		}))
		return event;
	},

	mounted() {
		let hiddenId = this.el.getAttribute("data-hidden-id")
		let hiddenIdFull = '#' + hiddenId

		let $selects = jQuery(this.el).find("select");
		let $select = $selects[0]

		$(hiddenIdFull).val(1).change()
		$select.dispatchEvent(new Event("input", {
			bubbles: true,
			cancelable: true
		}))

		this.initSelect2(this.el, this, hiddenIdFull, $selects)
	}
}





import flatpicker from "flatpickr";


Hooks.DatePicker = {

	updated() {
		console.log("Update")
		console.log(this.picker.open())
	},
	mounted() 
	{
		console.log(this.el)
		this.picker = flatpickr("#container", {appendTo: this.el, static: false, inline: true, wrap: false, clickOpens: true, mode: 'range', onChange: (e) => 
		{
			console.log("Piou")
			var end = document.getElementById('shopping_basket_end_dt')
			var st = document.getElementById('shopping_basket_start_dt');
			console.log(e)
	
			if(e[0]) {
				console.log(e[0])
				
				var value = e[0].getFullYear() +"-"+ e[0].getMonth()  +"-" + e[0].getDate()
				console.log(value)
				st.value =  (e[0].toISOString())
				console.log(st)
				st.dispatchEvent(new Event('input', {
				  view: window,
				  bubbles: true,
				  cancelable: true
				}))
			}
	
			if(e[1]) {
				end.value = e[1].toISOString()
				end.dispatchEvent(new Event('input', {
				  view: window,
				  bubbles: true,
				  cancelable: true
				}))
			}


		console.log(e[0])
		console.log(e[1])
		console.log("Something")
		return;
		} 
       })
	this.picker.open()
   }
	
}


import 'tui-date-picker/dist/tui-date-picker.css';
import 'tui-time-picker/dist/tui-time-picker.css';

function formatTime(time) {
  const hours = `${time.getHours()}`.padStart(2, '0');
  const minutes = `${time.getMinutes()}`.padStart(2, '0');

  return `${hours}:${minutes}`;
}

function get_default_view() {
	if(window.innerWidth > 700){
		return "week";
	} else {
		return "day";
	}
}

function for_calendar(meals, calendar) {

	var date = new Date();
	for (let i = 0; i < meals.length; i++) {
		let meal = meals[i];
		const startDt = Date.parse(meal.start)
		const endDT = Date.parse(meal.end)
		const newDate = startDt - (date.getTimezoneOffset() * 60 * 1000)
		const newDateAfter = endDT - (date.getTimezoneOffset() * 60 * 1000)
		const dt = new Date(newDate)
		const dta = new Date(newDateAfter)

		let colorText = "#004300";
		let colorBack = "#ffcc90";
		let lightColorBack = "#c8e6c9";

		calendar.createEvents([{
			id: meal.id,
			calendarId: 'cal1',
			title: meal.title + "(" + meal.sub_title + ")",
			body: 'TOAST UI Calendar',
			start: dt,
			body: meal.sub_title,
			end: dta,
			location: 'Meeting Room A',
			attendees: ['A', 'B', 'C'],
			category: 'time',
			state: 'Busy',
			isReadOnly: false,
			color: colorText,
			backgroundColor: colorBack,
			customStyle: {
				fontStyle: 'italic',
				fontSize: '15px',
			},
		}, // EventObject
		]);
	}
}



function  mount_callendar(parent_view) {
		const Calendar = tui.Calendar;
		const container = document.getElementById('calendar');
		const options = {
			defaultView: get_default_view(),
			usageStatistics: false,
			isReadOnly: false,
			useFormPopup: false,
			useDetailPopup: false,
			  theme: {
   				 week: {
    				},
			  },
			week: {
				taskView: true,
				startDayOfWeek: 1,
				visibleScheduleCount: 14,
				showNowIndicator: false,
				scheduleView: true,
				hourStart: 6,
				hourEnd: 24,
				eventView: ['time'],
				taskView: false,
			},
			timezone: {
				zones: [{
					timezoneName: 'Europe/Athens',
					displayLabel: 'Athens',
				}, ],
			},
			calendars: [{
				id: 'cal1',
				name: 'Personal',
				backgroundColor: 'blue',
			}, ],
		};

		const calendar = new Calendar(container, options);
		const prevButton = document.getElementById('callendar_prev_button');
		prevButton.addEventListener('click', function(e) {
			calendar.prev();
});


		const nextButton = document.getElementById('callendar_next_button');
		nextButton.addEventListener('click', function(e) {
			calendar.next();
});

		window.addEventListener(`phx:create-meal`, (e) => {
			var start = e.detail.start
			var end = e.detail.end
			calendar.createEvents([{
				id: 'event1',
				calendarId: 'cal1',
				title: 'Some Title',
				start: start,
				end: end,
			}, ]);

		})

		calendar.on('clickEvent', ({
			event
		}) => {
			parent_view.pushEvent("edit_modal", {
				id: event.id
			})
		});

		calendar.on('selectDateTime', ({
			start,
			end
		}) => {
			console.log("Click Event9")
			parent_view.pushEvent("initial_modal", {
				start: start,
				end: end
			})
		});




		calendar.on({
			'clickSchedule': function(e) {
				console.log('clickSchedule', e);
			},
			'beforeCreateSchedule': function(e) {
				console.log('beforeCreateSchedule', e);
				// open a creation popup (your custom popup)!!
			},
			'beforeCreateEvent': function(e) {
				console.log('beforeCreateEvent', e);
				// open a creation popup (your custom popup)!!
			},
			'beforeUpdateEvent': function(e) {
				console.log('beforeUpdateEvent', e);
				// open a creation popup (your custom popup)!!
			},
			'clickDayName': function(e) {
				console.log('clickDayName', e);
				// open a creation popup (your custom popup)!!
			},
			'clickEvent': function(e) {
				console.log('clickEvent', e);
				// open a creation popup (your custom popup)!!
			},
			'selectDateTime': function({
				start,
				end
			}) {
				console.log('selectDateTime', start);
				console.log('selectDateTimeEnd', end)
				// open a creation popup (your custom popup)!!
			},

			'beforeUpdateSchedule': function(e) {
				console.log('beforeUpdateSchedule', e);
				e.schedule.start = e.start;
				e.schedule.end = e.end;
				cal.updateSchedule(e.schedule.id, e.schedule.calendarId, e.schedule);
			},
			'beforeDeleteSchedule': function(e) {
				console.log('beforeDeleteSchedule', e);
				cal.deleteSchedule(e.schedule.id, e.schedule.calendarId);
			}
		});
		return calendar ;

	}

Hooks.HiddenCalendar = {

	mounted() {
		const toggle_button = document.getElementById('button_hidde_calendar');
		toggle_button.addEventListener("click", () => {
	        	this.para = document.getElementById("calendar_controlls");
			this.para.classList.toggle("calendar_controlls_open")
		});

	      	this.origin_callendar = mount_callendar(this);
		mounted_func(this, null, this.origin_callendar);
		window.addEventListener(`phx:create_meals`, (e) => {
			this.meals = e.detail['meals']
			for_calendar(this.meals, this.origin_callendar);
		})
	}
}


	function mounted_func(parent_view, start_date, origin_callendar) {
		if(! origin_callendar) {
		       	parent_view.origin_callendar = mount_callendar(parent_view); 
			origin_callendar = parent_view.origin_callendar;
		}
	

		const Calendar = tui.Calendar;
		const container = document.getElementById('hidden_calendar');
		const options = {
			defaultView: "month",
			usageStatistics: false,
			isReadOnly: false,
			useFormPopup: false,
			useDetailPopup: false,
			  theme: {
				 month: {
					backgroundColor: 'white',
				 },
   				 week: {
    				},
			  },

			week: {
				taskView: true,
				startDayOfWeek: 1,
				visibleScheduleCount: 14,
				showNowIndicator: false,
				scheduleView: true,
				hourStart: 6,
				hourEnd: 24,
				eventView: ['time'],
				taskView: false,
			},
			timezone: {
				zones: [{
					timezoneName: 'Europe/Athens',
					displayLabel: 'Athens',
				}, ],
			},
			calendars: [{
				id: 'cal2',
				name: 'Personal',
				backgroundColor: 'blue',
			}, ],
		};

		var calendar = new Calendar(container, options);
		if(start_date) {
			console.log(start_date)
			console.log(origin_callendar);
			console.log("Start date--------------------------------------")
			origin_callendar.setDate(start_date);
		}
		calendar.on('afterRenderEvent', ({
			event
		}) => {
			console.log("Hei ho---------------->")
			var elements2 = document.getElementsByClassName('toastui-calendar-accumulated');
			console.log(elements2)
			console.log("element 222")
			for (let s of elements2) {
				console.log(s)
				console.log("22222")
				s.remove();
			}
			return null;

		});

calendar.setTheme({
  month: {
    dayExceptThisMonth: {
    },
    moreView: {
	    backgroundColor: 'red'
    }
  },
});
		calendar.on('selectDateTime', ({
			start,
			end
		}) => {
			origin_callendar.setDate(start);
			calendar.setDate(start);
			var elements2 = document.getElementsByClassName('toastui-calendar-accumulated');
	        	let para = document.getElementById("calendar_controlls");
			para.classList.toggle("calendar_controlls_open")
			calendar.destroy();
			origin_callendar.destroy();
			mounted_func(parent_view, start, this);
			for_calendar(parent_view.meals, parent_view.origin_callendar);

		});

		calendar.on('clickEvent', ({
			event
		}) => {
			console.log("another event")
			console.log(event)
		});
		calendar.on('clickSchedule', ({
			event
		}) => {
			console.log(event)
		});

		calendar.on('beforeCreateSchedule', ({
			event
		}) => {
			console.log("Click Event4")
			console.log(event)
		});

		calendar.on('beforeCreateEvent', ({
			event
		}) => {
			console.log("Click Event5")
			console.log(event)
		});

		calendar.on('beforeUpdateEvent', ({
			event
		}) => {
			console.log("Click Event6")
			console.log(event)
		});

		calendar.on('clickDayName', ({
			event
		}) => {
			console.log("Click Event7")
			console.log(event)
		});

		calendar.on('afterRenderEvent', ({
			event
		}) => {});


		calendar.on('clickMoreEventsBtn', ({
			event
		}) => {
			console.log("Click Event10")
			console.log(event)
		});

		calendar.on('clickTimezoneCollapseBtn', ({
			event
		}) => {
			console.log("Click Event11")
			console.log(event)
		});
	}
export {Hooks}
