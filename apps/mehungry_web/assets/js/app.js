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
   
// Show progress bar on live navigation and form submits
let Hooks = {}
Hooks.SelectIngredient = {

  initSelect2() {
    let hook = this,
        $select = jQuery(hook.el).find("select");
    console.log($select)
    $select.select2().on("select2:select", (e) => hook.selected(hook, e))
    
    $( "#submit_button_ingredient" ).click(function() {
        var text_ingredient = $('#ingredient_id_ph').val();
        var text_quantity = $('#quantity_placeholder').val();
        hook.pushEvent("new_ingredient_entry",{ingredient_id: text_ingredient, quantity: text_quantity, measurement_unit_id: 1});
    });

    return $select;
  },

  mounted() {
    this.initSelect2();
  },

  selected(hook, event) {
    let id = event.params.data.id;
    $('#ingredient_id_ph').value = id;
    hook.pushEventTo(this.el, "ingredient_selected", {ingredient_id: id})
  }
}

let liveSocket = new LiveSocket("/live", Socket, {hooks: Hooks, params: {_csrf_token: csrfToken}})
 
// connect if there are any LiveViews on the page
liveSocket.connect()
      
// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket 

