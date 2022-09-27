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

Hooks.Mu = {

  initSelect2() {
    let hook = this;
    let $selects = jQuery(hook.el).find("select");
    let $select_mu = $selects[0]

    $selects.select2().on("select2:select", (e) => hook.selected_mu(hook, e)) 
    hook.pushEventTo($selects[0], "mu_selected", {mu_id: $selects[0].value}) 
    $('#mu_id_ph').val($selects[0].value)
    return $select_mu;
  },
  
  mounted() {
    this.initSelect2();
  },

  selected_mu(hook, event) {
    let id = event.params.data.id;
    hook.pushEventTo(this.el, "mu_selected", {mu_id: id}) 
    $('#mu_id_ph').val(id)
  }
}

Hooks.SelectIngredient = {

  initSelect2() {
    console.log("init2")
    let hook = this;
    let $selects = jQuery(hook.el).find("select");
    let $select_ingredient = $selects[0]

    $selects.select2().on("select2:select", (e) => hook.selected_ingredient(hook, e));
    hook.pushEventTo($selects[0], "ingredient_selected", {ingredient_id: $selects[0].value});
    $('#ingredient_id_ph').val($selects[0].value); 

    return $select_ingredient;
  },

  mounted() {
    this.initSelect2();
  },

  selected_ingredient(hook, event) {
    let id = event.params.data.id;
    $('#ingredient_id_ph').val(id).change();
    hook.pushEventTo(this.el, "ingredient_selected", {ingredient_id: id})
  },
}

let liveSocket = new LiveSocket("/live", Socket, {hooks: Hooks, uploaders: Uploaders, params: {_csrf_token: csrfToken}})
 
// connect if there are any LiveViews on the page
liveSocket.connect()
      
// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket 
