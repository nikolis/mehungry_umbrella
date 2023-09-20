
let Hooks = {}


//The clickable area falls within  the drop zone which creates problems to the click to upload functionality which is why This triggered is used to propagate the click to the apropriate ellement  
Hooks.ImageSelect = {
	mounted() {
		$('#lab1').click(function() {
			var idd = $('#lab1').attr('for')
			$("#" + idd).trigger("click")
		});
	}
}


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

Hooks.ModalHook = {
	mounted() {
		document.body.classList.add("modal-open");
		const modal = document.getElementById("modal");
		const close = document.getElementsByClassName("modal-close")[0];

		close.addEventListener('click', function(e) {
			console.log('Click happened for: ' + e.target.id);
			modal.classList.add("is-closing")
		});

	},

	destroyed() {
		document.body.classList.remove("modal-open");
	}

}


Hooks.Select2Multi = {

	initSelect2(element, hook, hiddenIdFull, selects) {
		let hook2 = this;
		let $select = selects[0]
		$('#recipe_select_select').val($(hiddenIdFull).val())


		selects.select2().on("change", (e) =>
			hook.item_selected($select, e, hiddenIdFull)
		)

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
		let hiddenIdFull = '#' + hiddenId

		let $selects = jQuery(this.el).find("select");
		let $select = $selects[0]

		this.initSelect2(this.el, this, hiddenIdFull, $selects)
	}
}



import flatpicker from "flatpickr";


Hooks.DatePicker = {
	mounted() {
		flatpicker("input[type=datetime]", {})
	}
}


import 'tui-date-picker/dist/tui-date-picker.css';
import 'tui-time-picker/dist/tui-time-picker.css';


Hooks.Calendar = {

	mounted() {
		const Calendar = tui.Calendar;
		const container = document.getElementById('calendar');

		const options = {
			defaultView: 'week',
			usageStatistics: false,
			isReadOnly: false,
			useFormPopup: false,
			useDetailPopup: false,
			week: {
				taskView: false,
				startDayOfWeek: 1,
				visibleScheduleCount: 14,
				showNowIndicator: false,
				scheduleView: false,
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
				backgroundColor: '#03bd9e',
			}, ],
		};

		const calendar = new Calendar(container, options);

		window.addEventListener(`phx:create_meals`, (e) => {
			let meals = e.detail['meals']
			var date = new Date();
			for (let i = 0; i < meals.length; i++) {
				let meal = meals[i];
				const startDt = Date.parse(meal.start)
				const endDT = Date.parse(meal.end)
				const newDate = startDt - (date.getTimezoneOffset() * 60 * 1000)
				const newDateAfter = endDT - (date.getTimezoneOffset() * 60 * 1000)
				const dt = new Date(newDate)
				const dta = new Date(newDateAfter)
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
					color: '#fff',
					backgroundColor: '#ccc',
					customStyle: {
						fontStyle: 'italic',
						fontSize: '15px',
					},
				}, // EventObject
				]);
			}
		})



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
			this.pushEvent("edit_modal", {
				id: event.id
			})
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

		calendar.on('selectDateTime', ({
			start,
			end
		}) => {
			console.log("Click Event9")
			this.pushEvent("initial_modal", {
				start: start,
				end: end
			})
		});

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

	}
}


export {Hooks}
