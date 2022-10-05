// We need to import the CSS so that webpack will load it.
// The MiniCssExtractPlugin is used to separate it out into
// its own CSS file.
import "../css/app.css"
// webpack automatically bundles all modules in your
// entry points. Those entry points can be configured
// in "webpack.config.js".
//
// Import deps with the dep name or local files with a relative path, for example:
//
//     import {Socket} from "phoenix"
//     import socket from "./socket"
import "phoenix_html"          
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import jQuery from "jquery"
import select2 from "select2"
 
$(document).ready(function () {
  $(".nav-toggler").each(function (_, navToggler) {
    var target = $(navToggler).data("target");
    $(navToggler).on("click", function () {
      $(target).animate({
        height: "toggle",
      });
    });
  });
});
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let Uploaders = {}

Uploaders.S3 = function(entries, onViewError){
  entries.forEach(entry => {
    let formData = new FormData()
    let {url, fields} = entry.meta
    Object.entries(fields).forEach(([key, val]) => formData.append(key, val))
    formData.append("file", entry.file)
    let xhr = new XMLHttpRequest()
    onViewError(() => xhr.abort())
    xhr.onload = () => xhr.status === 204 ? entry.progress(100) : entry.error()
    xhr.onerror = () => entry.error()
    xhr.upload.addEventListener("progress", (event) => {
      if(event.lengthComputable){
        let percent = Math.round((event.loaded / event.total) * 100)
        if(percent < 100){ entry.progress(percent) }
      }
    })

    xhr.open("POST", url, true)
    xhr.send(formData)
  })
}

let Hooks = {}
Hooks.Select2 = {

  initSelect2(element, hook, hiddenIdFull, selects) {
    let hook2 = this;
    let $select = selects[0]
    
    selects.select2().on("select2:select", (e) => 
      hook.item_selected($select, e, hiddenIdFull)) 
      return element 
    },

  item_selected(element, event, hiddenIdFull) {
    let id = event.params.data.id;
    $(hiddenIdFull).val(id).change()
    element.dispatchEvent(new Event("input", {bubbles: true, cancelable: true}))
    return event ; 
  },

  mounted() {
    let tempId = this.el.getAttribute("data-temp-id") 
    let hiddenId = this.el.getAttribute("data-hidden-id") 
    let hiddenIdFull = '#'+hiddenId  
  
    let $selects = jQuery(this.el).find("select");
    let $select = $selects[0]

    $(hiddenIdFull).val(1).change()
    $select.dispatchEvent(new Event("input", {bubbles: true, cancelable: true}))

    this.initSelect2(this.el, this, hiddenIdFull, $selects)
  }
}

let liveSocket = new LiveSocket("/live", Socket, {hooks: Hooks, uploaders: Uploaders, params: {_csrf_token: csrfToken}})
 
// connect if there are any LiveViews on the page
liveSocket.connect()
      
// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket



