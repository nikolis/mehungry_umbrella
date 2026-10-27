import "selectize";

let Hooks = {}

import "vega"
import "vega-lite"
import vegaEmbed from "vega-embed"

Hooks.ResponsiveChart = {
  mounted() {
    this.el._id = this.el.dataset.id
    const componentId = this.el.dataset.origin_id;
    const measure = () => {
      const width = this.el.offsetWidth

      this.pushEventTo(componentId, "resize", {
        width: width
      })
    }

    // initial measure (IMPORTANT for mobile)
    setTimeout(measure, 0)

    window.addEventListener("resize", measure)
  }
}


Hooks.VegaLite = {
  mounted() {
    const spec = JSON.parse(this.el.dataset.spec)
    vegaEmbed(this.el, spec).then(result => { this._view = result.view })

    this.handleResize = () => {
      const width = this.el.offsetWidth
      this.pushEvent("resize_chart", { width })
    }

    window.addEventListener("resize", this.handleResize)
    this.handleResize()
  },
  updated() {
    if (this._view) { this._view.finalize(); this._view = null }
    const spec = JSON.parse(this.el.dataset.spec)
    vegaEmbed(this.el, spec).then(result => { this._view = result.view })
  },
  destroyed() {
    window.removeEventListener("resize", this.handleResize)
    if (this._view) { this._view.finalize(); this._view = null }
  }
}


Hooks.RecipeDetailTimer = {
  mounted() {
    // The recipe detail content is now in the DOM — data is present, so tell
    // app.js to drop the instant loading skeleton. This is the deterministic
    // hide signal (page-loading-stop and the safety timeout are backstops).
    window.dispatchEvent(new CustomEvent('mehungry:recipe-loaded'))
  }
}

Hooks.Copy = {
  mounted() {
    let { to } = this.el.dataset;
    const showFeedback = () => {
      const span = this.el.querySelector("span") || this.el;
      const prev = span.textContent;
      span.textContent = "Copied!";
      setTimeout(() => { span.textContent = prev; }, 2000);
    };
    this.el.addEventListener("click", (ev) => {
      ev.preventDefault();
      const target = document.querySelector(to);
      if (!target) return;
      const text = target.value;
      navigator.clipboard.writeText(text)
        .then(showFeedback)
        .catch(() => {
          // last-resort fallback for HTTP or old browsers
          target.removeAttribute("readonly");
          target.select();
          document.execCommand("copy");
          target.setAttribute("readonly", "");
          showFeedback();
        });
    });
  },
}

Hooks.WebShare = {
  mounted() {
    if (!navigator.share) {
      const span = this.el.querySelector("span");
      if (span) span.textContent = "Copy Link";
    }
    this.el.addEventListener("click", (ev) => {
      ev.preventDefault();
      ev.stopPropagation();
      const url = this.el.dataset.url;
      const title = this.el.dataset.title || "Check out this recipe on Mehungry";
      // Optional long-form body (e.g. a text-only plan caption). When present it
      // rides along in the native share sheet, and is what we copy on fallback.
      const text = this.el.dataset.text;
      const btn = this.el;
      const originalText = btn.querySelector("span") ? btn.querySelector("span").textContent : btn.textContent.trim();

      const showFeedback = (msg) => {
        const span = btn.querySelector("span") || btn;
        const prev = span.textContent;
        span.textContent = msg;
        setTimeout(() => { span.textContent = prev; }, 2000);
      };

      // When a body is supplied, copying it (not just the URL) preserves the
      // whole post on platforms without a native share sheet.
      const clipboardText = text ? (url ? `${text}\n${url}` : text) : url;

      if (navigator.share) {
        const payload = text ? { title, text, url } : { title, url };
        navigator.share(payload)
          .then(() => showFeedback("Shared!"))
          .catch((err) => { if (err.name !== "AbortError") console.error("Share failed", err); });
      } else {
        navigator.clipboard.writeText(clipboardText)
          .then(() => showFeedback("Copied!"))
          .catch(() => {
            // last-resort fallback for HTTP or old browsers
            const ta = document.createElement("textarea");
            ta.value = clipboardText;
            ta.style.position = "fixed";
            ta.style.opacity = "0";
            document.body.appendChild(ta);
            ta.select();
            document.execCommand("copy");
            document.body.removeChild(ta);
            showFeedback("Copied!");
          });
      }
    });
  },
}

Hooks.FocusHook = {
  mounted() {
  }
}

Hooks.ViewportResizeHooks = {

  mounted () {
    // Direct push of current window size to properly update view
    this.pushResizeEvent()
    resizeHandler = _.debounce(() => {
      this.pushResizeEvent()
    }, 100)
    window.addEventListener('resize', resizeHandler)
  },

  pushResizeEvent () {
    console.log("Hereerereerer")
    console.log(window.screen.width)
    console.log(window)
    this.pushEvent('viewport_resize', {
      width: window.screen.width,
      height: window.screen.height
    })
  },

  turbolinksDisconnected () {
    window.removeEventListener('resize', resizeHandler)
  }
}
Hooks.SelectComponentList = {
  mounted() {
    setTimeout(() => {
    console.log(this.el.scrollIntoView({block: "center", behavior: "smooth"}));
}, 200);
  },
  updated() {
    console.log("updated:")
    this.el.scrollIntoView({block: "center", behavior: "smooth"});  
  },
}

Hooks.ScrolledIntoEndOfScreen = {
  mounted() {
    setTimeout(() => {
    console.log(this.el.scrollIntoView({block: "end", behavior: "smooth"}));
}, 200);
  },
  updated() {
    console.log("updated:")
    this.el.scrollIntoView({block: "end", behavior: "smooth"});  
  },
}


Hooks.SelectComponent = {
  mounted() {
    this.ref = this.el;
    const refAt = this.ref.getAttribute("data-reference-id")

    const originalID = this.el.id
    const referenceIndex = this.ref.getAttribute("data-reference-index")

    var event_listener;
    if (referenceIndex) {
      event_listener = "phx:selected_id"+ referenceIndex + refAt
    }
    else {
      event_listener = "phx:selected_id"+ refAt
    }
    window.addEventListener(event_listener, (e) => {
      console.log("Event Listener")
      let el = document.getElementById(originalID)
      for (const child of this.el.children) {
        if(child.id !=null && child.id.includes(refAt)){
            if(child.tagName == "INPUT"){
              
              child.value = e.detail.id
      			  $("#" + child.id).val(e.detail.id).change()
              var ret = child.dispatchEvent(new Event("input", {
                  bubbles: true,
                  cancelable: false,
                  detail: {id: e.detail.id},
              }));
            }
        }
      }
    });
  }
}
// In your app.js or hooks file
Hooks.SelectComponentDeep = {
  mounted() {
    // Store component ID for reference
    this.componentId = this.el.id
    
    // Handle selection events to update hidden input
    this.handleEvent("select_item_selected", ({id, input_key, component_id}) => {
      // Only process if it's for this component
      if (component_id !== this.componentId) return
      
      const hiddenInput = this.el.querySelector(`input[name$="[${input_key}]"]`)
      if (hiddenInput) {
        hiddenInput.value = id
        hiddenInput.dispatchEvent(new Event("change", { bubbles: true }))
      }
    })

    this.handleEvent("selection_cleared", ({input_key, component_id}) => {
      // Only process if it's for this component
      if (component_id !== this.componentId) return
      
      const hiddenInput = this.el.querySelector(`input[name$="[${input_key}]"]`)
      if (hiddenInput) {
        hiddenInput.value = ""
        hiddenInput.dispatchEvent(new Event("change", { bubbles: true }))
      }
    })
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
/*
Hooks.AccordionHook = {
	page() {
	},
	mounted() {
		const accordion = document.querySelector(".accordion");
    console.log(accordion.id);

    accordion.addEventListener("click", (e) => {
  const activePanel = e.target.closest(".accordion-panel");
  if (!activePanel) return;
  toggleAccordion(activePanel);
  e.stopPropagation();
});

function toggleAccordion(panelToActivate) {
  const activeButton = panelToActivate.querySelector("button");
  const activePanel = panelToActivate.querySelector(".accordion-content");
  const activePanelIsOpened = activeButton.getAttribute("aria-expanded");
  console.log(activePanelIsOpened)
  console.log("adfs")
  if (activePanelIsOpened === true || activePanelIsOpened === "true") {
    console.log("Got in here")
    panelToActivate
      .querySelector("button")
      .setAttribute("aria-expanded", false);

    panelToActivate
      .querySelector(".accordion-content")
      .setAttribute("aria-hidden", true);
  } else {
    console.log("Got in here through")
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
*/
Hooks.GoogleLoginHook = {
	mounted() {
		console.log("Mounter")
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
		// Local midnight for the picked day as a naive ISO string. `toISOString()`
		// would convert to UTC first, so for a user east of UTC (e.g. Greece,
		// UTC+2/+3) the selected day would be shifted back by one, pulling the
		// basket's meal-range query onto the wrong days. The server parses this
		// with `NaiveDateTime.from_iso8601!/1`, which ignores any offset anyway.
		const toNaive = (d) => {
			const pad = (n) => String(n).padStart(2, '0')
			return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) + "T00:00:00"
		}
		const setDate = (el, d) => {
			el.value = toNaive(d)
			el.dispatchEvent(new Event('input', { view: window, bubbles: true, cancelable: true }))
		}

		this.picker = flatpickr("#container", {appendTo: this.el, static: false, inline: true, wrap: false, clickOpens: true, mode: 'range', onChange: (e) =>
		{
			var end = document.getElementById('shopping_basket_end_dt')
			var st = document.getElementById('shopping_basket_start_dt');

			if(e[0]) {
				setDate(st, e[0])
			}

			if(e[1]) {
				setDate(end, e[1])
			}
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
  return calendar; 
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
		};//options

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
      calendar.clear();
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
				startDayOfWeek: 1,
				visibleScheduleCount: 14,
				showNowIndicator: false,
				scheduleView: true,
				hourStart: 6,
				hourEnd: 12,
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

Hooks.HiddenCalendar = {

	mounted() {
		const toggle_button = document.getElementById('button_hidde_calendar');
		toggle_button.addEventListener("click", () => {
	        	this.para = document.getElementById("calendar_controlls");
			this.para.classList.toggle("calendar_controlls_open")
		});

	  this.origin_callendar = mount_callendar(this);
    console.log(this.origin_callendar)
    console.log("This origin callendar ");
		mounted_func(this, null, this.origin_callendar);
		window.addEventListener(`phx:create_meals`, (e) => {
			this.meals = e.detail['meals']
			for_calendar(this.meals, this.origin_callendar);
		})
		window.addEventListener(`phx:go_to_date`, (e) => {
			var date = e.detail['date']
      console.log(date)
			result = this.origin_callendar.setDate(date)
      console.log(result)
		})

	}
}

	function mounted_func(parent_view, start_date, origin_callendar) {
    console.log("original calldndar mounted")
    console.log(origin_callendar)
    console.log("----")
    const ori_cale = origin_callendar;
    console.log("ori_cale")
    console.log(ori_cale)
		if(! origin_callendar) {
		  parent_view.origin_callendar = mount_callendar(parent_view); 
			origin_callendar = parent_view.origin_callendar;
		}
	

		const Calendar = tui.Calendar;
		const container = document.getElementById('hidden_calendar');

		var calendar = new Calendar(container, options);
		if(start_date) {
			console.log(start_date)
			console.log(origin_callendar);
			console.log("Start date--------------------------------------")
      console.log(origin_callendar)
    
			parent_view.origin_callendar.setDate(start_date);
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
			mounted_func(parent_view, start, null);
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




// assets/js/hooks/accordion_hook.js
// assets/js/hooks/accordion_hook.js

Hooks.AccordionHook = {
  mounted() {
    this.accordion = this.el;
    this.initPanels();
    this.handleClick = this.handleClick.bind(this);
    this.accordion.addEventListener("click", this.handleClick);
  },
  
  initPanels() {
    const panels = this.accordion.querySelectorAll(".accordion-panel");
    
    panels.forEach((panel) => {
      const button = panel.querySelector("button");
      const content = panel.querySelector(".accordion-content");
      
      if (button && content) {
        // Store initial closed state
        button.setAttribute("aria-expanded", "false");
        content.setAttribute("aria-hidden", "true");
      }
    });
  },
  
  handleClick(event) {
    const panel = event.target.closest(".accordion-panel");
    if (!panel) return;
    
    const button = panel.querySelector("button");
    const content = panel.querySelector(".accordion-content");
    
    if (!button || !content) return;
    
    const isExpanded = button.getAttribute("aria-expanded") === "true";
    
    if (isExpanded) {
      // Close
      button.setAttribute("aria-expanded", "false");
      content.setAttribute("aria-hidden", "true");
      content.classList.add("hidden");
    } else {
      // Open
      button.setAttribute("aria-expanded", "true");
      content.setAttribute("aria-hidden", "false");
      content.classList.remove("hidden");
    }
    
    event.stopPropagation();
  },
  
  updated() {
    // Re-attach to any new panels after LiveView updates
    this.initPanels();
  },
  
  destroyed() {
    if (this.accordion && this.handleClick) {
      this.accordion.removeEventListener("click", this.handleClick);
    }
  }
};





// Renders a Cloudflare Turnstile widget inside a LiveView-managed form.
// Loads the Turnstile api.js once, then explicitly renders the widget so it
// survives LiveView DOM patching (the auto `.cf-turnstile` render does not).
// The widget injects a hidden `cf-turnstile-response` input into the form, so
// its token is included in the `phx-submit` params.
Hooks.Turnstile = {
  mounted() {
    this.renderWidget()
  },
  renderWidget() {
    const sitekey = this.el.dataset.sitekey
    if (!sitekey) return

    const doRender = () => {
      if (window.turnstile && this.el && !this.el.dataset.rendered) {
        this.widgetId = window.turnstile.render(this.el, { sitekey })
        this.el.dataset.rendered = "true"
      }
    }

    if (window.turnstile) {
      doRender()
    } else if (!document.getElementById("cf-turnstile-script")) {
      const script = document.createElement("script")
      script.id = "cf-turnstile-script"
      script.src = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"
      script.async = true
      script.defer = true
      script.onload = doRender
      document.head.appendChild(script)
    } else {
      // Script tag exists but turnstile not ready yet — poll briefly.
      const t = setInterval(() => {
        if (window.turnstile) {
          clearInterval(t)
          doRender()
        }
      }, 100)
      setTimeout(() => clearInterval(t), 5000)
    }
  },
  destroyed() {
    if (this.widgetId && window.turnstile) {
      try { window.turnstile.remove(this.widgetId) } catch (_e) {}
    }
  }
}

// Research reader: when the server has put the page in "note mode"
// (data-note-mode="true"), capturing a text selection in the article pushes the
// selected passage + its paragraph/section anchors back so the note form can
// prefill the sub-text. Cursor affordance is handled server-side via a CSS class.
Hooks.NoteSelection = {
  mounted() {
    this.onMouseUp = () => {
      if (this.el.dataset.noteMode !== "true") return

      const selection = window.getSelection()
      // Collapse whitespace so the stored quote matches the paragraph text (which
      // the server re-locates with a whitespace-tolerant search to highlight it).
      const text = selection ? selection.toString().replace(/\s+/g, " ").trim() : ""
      if (!text) return

      let node = selection.anchorNode
      if (node && node.nodeType === Node.TEXT_NODE) node = node.parentElement

      const paragraph = node && node.closest('[id^="par-"]')
      const section = node && node.closest('[id^="sec-"]')

      // Only accept selections that land inside the article.
      if (!this.el.contains(node)) return

      this.pushEvent("select_passage", {
        text: text,
        paragraph_id: paragraph ? paragraph.id.replace(/^par-/, "") : null,
        section_id: section ? section.id.replace(/^sec-/, "") : null
      })
    }

    this.el.addEventListener("mouseup", this.onMouseUp)
  },
  destroyed() {
    this.el.removeEventListener("mouseup", this.onMouseUp)
  }
}

export {Hooks}
