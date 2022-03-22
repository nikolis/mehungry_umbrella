/******/ (function(modules) { // webpackBootstrap
/******/ 	// The module cache
/******/ 	var installedModules = {};
/******/
/******/ 	// The require function
/******/ 	function __webpack_require__(moduleId) {
/******/
/******/ 		// Check if module is in cache
/******/ 		if(installedModules[moduleId]) {
/******/ 			return installedModules[moduleId].exports;
/******/ 		}
/******/ 		// Create a new module (and put it into the cache)
/******/ 		var module = installedModules[moduleId] = {
/******/ 			i: moduleId,
/******/ 			l: false,
/******/ 			exports: {}
/******/ 		};
/******/
/******/ 		// Execute the module function
/******/ 		modules[moduleId].call(module.exports, module, module.exports, __webpack_require__);
/******/
/******/ 		// Flag the module as loaded
/******/ 		module.l = true;
/******/
/******/ 		// Return the exports of the module
/******/ 		return module.exports;
/******/ 	}
/******/
/******/
/******/ 	// expose the modules object (__webpack_modules__)
/******/ 	__webpack_require__.m = modules;
/******/
/******/ 	// expose the module cache
/******/ 	__webpack_require__.c = installedModules;
/******/
/******/ 	// define getter function for harmony exports
/******/ 	__webpack_require__.d = function(exports, name, getter) {
/******/ 		if(!__webpack_require__.o(exports, name)) {
/******/ 			Object.defineProperty(exports, name, { enumerable: true, get: getter });
/******/ 		}
/******/ 	};
/******/
/******/ 	// define __esModule on exports
/******/ 	__webpack_require__.r = function(exports) {
/******/ 		if(typeof Symbol !== 'undefined' && Symbol.toStringTag) {
/******/ 			Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' });
/******/ 		}
/******/ 		Object.defineProperty(exports, '__esModule', { value: true });
/******/ 	};
/******/
/******/ 	// create a fake namespace object
/******/ 	// mode & 1: value is a module id, require it
/******/ 	// mode & 2: merge all properties of value into the ns
/******/ 	// mode & 4: return value when already ns object
/******/ 	// mode & 8|1: behave like require
/******/ 	__webpack_require__.t = function(value, mode) {
/******/ 		if(mode & 1) value = __webpack_require__(value);
/******/ 		if(mode & 8) return value;
/******/ 		if((mode & 4) && typeof value === 'object' && value && value.__esModule) return value;
/******/ 		var ns = Object.create(null);
/******/ 		__webpack_require__.r(ns);
/******/ 		Object.defineProperty(ns, 'default', { enumerable: true, value: value });
/******/ 		if(mode & 2 && typeof value != 'string') for(var key in value) __webpack_require__.d(ns, key, function(key) { return value[key]; }.bind(null, key));
/******/ 		return ns;
/******/ 	};
/******/
/******/ 	// getDefaultExport function for compatibility with non-harmony modules
/******/ 	__webpack_require__.n = function(module) {
/******/ 		var getter = module && module.__esModule ?
/******/ 			function getDefault() { return module['default']; } :
/******/ 			function getModuleExports() { return module; };
/******/ 		__webpack_require__.d(getter, 'a', getter);
/******/ 		return getter;
/******/ 	};
/******/
/******/ 	// Object.prototype.hasOwnProperty.call
/******/ 	__webpack_require__.o = function(object, property) { return Object.prototype.hasOwnProperty.call(object, property); };
/******/
/******/ 	// __webpack_public_path__
/******/ 	__webpack_require__.p = "/js/";
/******/
/******/
/******/ 	// Load entry module and return exports
/******/ 	return __webpack_require__(__webpack_require__.s = 0);
/******/ })
/************************************************************************/
/******/ ({

/***/ "./js/app.js":
/*!*******************!*\
  !*** ./js/app.js ***!
  \*******************/
/*! no exports provided */
/***/ (function(module, __webpack_exports__, __webpack_require__) {

"use strict";
eval("__webpack_require__.r(__webpack_exports__);\n!(function webpackMissingModule() { var e = new Error(\"Cannot find module 'phoenix'\"); e.code = 'MODULE_NOT_FOUND'; throw e; }());\n/* harmony import */ var _socket__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(/*! ./socket */ \"./js/socket.js\");\n!(function webpackMissingModule() { var e = new Error(\"Cannot find module 'phoenix_html'\"); e.code = 'MODULE_NOT_FOUND'; throw e; }());\n// We need to import the CSS so that webpack will load it.\n// The MiniCssExtractPlugin is used to separate it out into\n// its own CSS file.\n// webpack automatically bundles all modules in your\n// entry points. Those entry points can be configured\n// in \"webpack.config.js\".\n//    \n// Import deps with the dep name or local files with a relative path, for example:\n//\n\n\n//# sourceURL=[module]\n//# sourceMappingURL=data:application/json;charset=utf-8;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoiLi9qcy9hcHAuanMuanMiLCJzb3VyY2VzIjpbIndlYnBhY2s6Ly8vLi9qcy9hcHAuanM/NzQ3MyJdLCJzb3VyY2VzQ29udGVudCI6WyIvLyBXZSBuZWVkIHRvIGltcG9ydCB0aGUgQ1NTIHNvIHRoYXQgd2VicGFjayB3aWxsIGxvYWQgaXQuXG4vLyBUaGUgTWluaUNzc0V4dHJhY3RQbHVnaW4gaXMgdXNlZCB0byBzZXBhcmF0ZSBpdCBvdXQgaW50b1xuLy8gaXRzIG93biBDU1MgZmlsZS5cblxuLy8gd2VicGFjayBhdXRvbWF0aWNhbGx5IGJ1bmRsZXMgYWxsIG1vZHVsZXMgaW4geW91clxuLy8gZW50cnkgcG9pbnRzLiBUaG9zZSBlbnRyeSBwb2ludHMgY2FuIGJlIGNvbmZpZ3VyZWRcbi8vIGluIFwid2VicGFjay5jb25maWcuanNcIi5cbi8vICAgIFxuLy8gSW1wb3J0IGRlcHMgd2l0aCB0aGUgZGVwIG5hbWUgb3IgbG9jYWwgZmlsZXMgd2l0aCBhIHJlbGF0aXZlIHBhdGgsIGZvciBleGFtcGxlOlxuLy9cbmltcG9ydCB7U29ja2V0fSBmcm9tIFwicGhvZW5peFwiXG5pbXBvcnQgc29ja2V0IGZyb20gXCIuL3NvY2tldFwiXG5cbmltcG9ydCBcInBob2VuaXhfaHRtbFwiXG4iXSwibWFwcGluZ3MiOiJBQUFBO0FBQUE7QUFBQTtBQUFBO0FBQUE7QUFDQTtBQUNBO0FBRUE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTsiLCJzb3VyY2VSb290IjoiIn0=\n//# sourceURL=webpack-internal:///./js/app.js\n");

/***/ }),

/***/ "./js/socket.js":
/*!**********************!*\
  !*** ./js/socket.js ***!
  \**********************/
/*! exports provided: default */
/***/ (function(module, __webpack_exports__, __webpack_require__) {

"use strict";
eval("__webpack_require__.r(__webpack_exports__);\n!(function webpackMissingModule() { var e = new Error(\"Cannot find module 'phoenix'\"); e.code = 'MODULE_NOT_FOUND'; throw e; }());\n// NOTE: The contents of this file will only be executed if\n// you uncomment its entry in \"assets/js/app.js\".\n// To use Phoenix channels, the first step is to import Socket,\n// and connect at the socket path in \"lib/web/endpoint.ex\".\n//\n// Pass the token on params as below. Or remove it\n// from the params if you are not using authentication.\n\nvar socket = new !(function webpackMissingModule() { var e = new Error(\"Cannot find module 'phoenix'\"); e.code = 'MODULE_NOT_FOUND'; throw e; }())(\"/socket\", {\n  params: {\n    token: window.userToken\n  }\n}); // When you connect, you'll often need to authenticate the client.\n// For example, imagine you have an authentication plug, `MyAuth`,\n// which authenticates the session and assigns a `:current_user`.\n// If the current user exists you can assign the user's token in\n// the connection for use in the layout.\n//  \n// In your \"lib/web/router.ex\":\n//\n//     pipeline :browser do    \n//       ...                   \n//       plug MyAuth           \n//       plug :put_user_token  \n//     end                     \n//\n//     defp put_user_token(conn, _) do\n//       if current_user = conn.assigns[:current_user] do\n//         token = Phoenix.Token.sign(conn, \"user socket\", current_user.id)\n//         assign(conn, :user_token, token)\n//       else\n//         conn\n//       end\n//     end\n//\n// Now you need to pass this token to JavaScript. You can do so\n// inside a script tag in \"lib/web/templates/layout/app.html.eex\":\n//\n//     <script>window.userToken = \"<%= assigns[:user_token] %>\";</script>\n//\n// You will need to verify the user token in the \"connect/3\" function\n// in \"lib/web/channels/user_socket.ex\":\n//\n//     def connect(%{\"token\" => token}, socket, _connect_info) do\n//       # max_age: 1209600 is equivalent to two weeks in seconds\n//       case Phoenix.Token.verify(socket, \"user socket\", token, max_age: 1209600) do\n//         {:ok, user_id} ->\n//           {:ok, assign(socket, :user, user_id)}\n//         {:error, reason} ->\n//           :error\n//       end\n//     end\n//\n// Finally, connect to the socket:\n\nsocket.connect(); // Now that you are connected, you can join channels with a topic:\n\nvar channel = socket.channel(\"topic:subtopic\", {});\nchannel.join().receive(\"ok\", function (resp) {\n  console.log(\"Joined successfully\", resp);\n}).receive(\"error\", function (resp) {\n  console.log(\"Unable to join\", resp);\n});\n/* harmony default export */ __webpack_exports__[\"default\"] = (socket);//# sourceURL=[module]\n//# sourceMappingURL=data:application/json;charset=utf-8;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoiLi9qcy9zb2NrZXQuanMuanMiLCJzb3VyY2VzIjpbIndlYnBhY2s6Ly8vLi9qcy9zb2NrZXQuanM/MTU1NCJdLCJzb3VyY2VzQ29udGVudCI6WyIvLyBOT1RFOiBUaGUgY29udGVudHMgb2YgdGhpcyBmaWxlIHdpbGwgb25seSBiZSBleGVjdXRlZCBpZlxuLy8geW91IHVuY29tbWVudCBpdHMgZW50cnkgaW4gXCJhc3NldHMvanMvYXBwLmpzXCIuXG5cbi8vIFRvIHVzZSBQaG9lbml4IGNoYW5uZWxzLCB0aGUgZmlyc3Qgc3RlcCBpcyB0byBpbXBvcnQgU29ja2V0LFxuLy8gYW5kIGNvbm5lY3QgYXQgdGhlIHNvY2tldCBwYXRoIGluIFwibGliL3dlYi9lbmRwb2ludC5leFwiLlxuLy9cbi8vIFBhc3MgdGhlIHRva2VuIG9uIHBhcmFtcyBhcyBiZWxvdy4gT3IgcmVtb3ZlIGl0XG4vLyBmcm9tIHRoZSBwYXJhbXMgaWYgeW91IGFyZSBub3QgdXNpbmcgYXV0aGVudGljYXRpb24uXG5cbmltcG9ydCB7U29ja2V0fSBmcm9tIFwicGhvZW5peFwiXG4gIFxubGV0IHNvY2tldCA9IG5ldyBTb2NrZXQoXCIvc29ja2V0XCIsIHtwYXJhbXM6IHt0b2tlbjogd2luZG93LnVzZXJUb2tlbn19KVxuXG4vLyBXaGVuIHlvdSBjb25uZWN0LCB5b3UnbGwgb2Z0ZW4gbmVlZCB0byBhdXRoZW50aWNhdGUgdGhlIGNsaWVudC5cbi8vIEZvciBleGFtcGxlLCBpbWFnaW5lIHlvdSBoYXZlIGFuIGF1dGhlbnRpY2F0aW9uIHBsdWcsIGBNeUF1dGhgLFxuLy8gd2hpY2ggYXV0aGVudGljYXRlcyB0aGUgc2Vzc2lvbiBhbmQgYXNzaWducyBhIGA6Y3VycmVudF91c2VyYC5cbi8vIElmIHRoZSBjdXJyZW50IHVzZXIgZXhpc3RzIHlvdSBjYW4gYXNzaWduIHRoZSB1c2VyJ3MgdG9rZW4gaW5cbi8vIHRoZSBjb25uZWN0aW9uIGZvciB1c2UgaW4gdGhlIGxheW91dC5cbi8vICBcbi8vIEluIHlvdXIgXCJsaWIvd2ViL3JvdXRlci5leFwiOlxuLy9cbi8vICAgICBwaXBlbGluZSA6YnJvd3NlciBkbyAgICBcbi8vICAgICAgIC4uLiAgICAgICAgICAgICAgICAgICBcbi8vICAgICAgIHBsdWcgTXlBdXRoICAgICAgICAgICBcbi8vICAgICAgIHBsdWcgOnB1dF91c2VyX3Rva2VuICBcbi8vICAgICBlbmQgICAgICAgICAgICAgICAgICAgICBcbi8vXG4vLyAgICAgZGVmcCBwdXRfdXNlcl90b2tlbihjb25uLCBfKSBkb1xuLy8gICAgICAgaWYgY3VycmVudF91c2VyID0gY29ubi5hc3NpZ25zWzpjdXJyZW50X3VzZXJdIGRvXG4vLyAgICAgICAgIHRva2VuID0gUGhvZW5peC5Ub2tlbi5zaWduKGNvbm4sIFwidXNlciBzb2NrZXRcIiwgY3VycmVudF91c2VyLmlkKVxuLy8gICAgICAgICBhc3NpZ24oY29ubiwgOnVzZXJfdG9rZW4sIHRva2VuKVxuLy8gICAgICAgZWxzZVxuLy8gICAgICAgICBjb25uXG4vLyAgICAgICBlbmRcbi8vICAgICBlbmRcbi8vXG4vLyBOb3cgeW91IG5lZWQgdG8gcGFzcyB0aGlzIHRva2VuIHRvIEphdmFTY3JpcHQuIFlvdSBjYW4gZG8gc29cbi8vIGluc2lkZSBhIHNjcmlwdCB0YWcgaW4gXCJsaWIvd2ViL3RlbXBsYXRlcy9sYXlvdXQvYXBwLmh0bWwuZWV4XCI6XG4vL1xuLy8gICAgIDxzY3JpcHQ+d2luZG93LnVzZXJUb2tlbiA9IFwiPCU9IGFzc2lnbnNbOnVzZXJfdG9rZW5dICU+XCI7PC9zY3JpcHQ+XG4vL1xuLy8gWW91IHdpbGwgbmVlZCB0byB2ZXJpZnkgdGhlIHVzZXIgdG9rZW4gaW4gdGhlIFwiY29ubmVjdC8zXCIgZnVuY3Rpb25cbi8vIGluIFwibGliL3dlYi9jaGFubmVscy91c2VyX3NvY2tldC5leFwiOlxuLy9cbi8vICAgICBkZWYgY29ubmVjdCgle1widG9rZW5cIiA9PiB0b2tlbn0sIHNvY2tldCwgX2Nvbm5lY3RfaW5mbykgZG9cbi8vICAgICAgICMgbWF4X2FnZTogMTIwOTYwMCBpcyBlcXVpdmFsZW50IHRvIHR3byB3ZWVrcyBpbiBzZWNvbmRzXG4vLyAgICAgICBjYXNlIFBob2VuaXguVG9rZW4udmVyaWZ5KHNvY2tldCwgXCJ1c2VyIHNvY2tldFwiLCB0b2tlbiwgbWF4X2FnZTogMTIwOTYwMCkgZG9cbi8vICAgICAgICAgezpvaywgdXNlcl9pZH0gLT5cbi8vICAgICAgICAgICB7Om9rLCBhc3NpZ24oc29ja2V0LCA6dXNlciwgdXNlcl9pZCl9XG4vLyAgICAgICAgIHs6ZXJyb3IsIHJlYXNvbn0gLT5cbi8vICAgICAgICAgICA6ZXJyb3Jcbi8vICAgICAgIGVuZFxuLy8gICAgIGVuZFxuLy9cbi8vIEZpbmFsbHksIGNvbm5lY3QgdG8gdGhlIHNvY2tldDpcbnNvY2tldC5jb25uZWN0KClcblxuLy8gTm93IHRoYXQgeW91IGFyZSBjb25uZWN0ZWQsIHlvdSBjYW4gam9pbiBjaGFubmVscyB3aXRoIGEgdG9waWM6XG5sZXQgY2hhbm5lbCA9IHNvY2tldC5jaGFubmVsKFwidG9waWM6c3VidG9waWNcIiwge30pXG5jaGFubmVsLmpvaW4oKVxuICAucmVjZWl2ZShcIm9rXCIsIHJlc3AgPT4geyBjb25zb2xlLmxvZyhcIkpvaW5lZCBzdWNjZXNzZnVsbHlcIiwgcmVzcCkgfSlcbiAgLnJlY2VpdmUoXCJlcnJvclwiLCByZXNwID0+IHsgY29uc29sZS5sb2coXCJVbmFibGUgdG8gam9pblwiLCByZXNwKSB9KVxuXG5leHBvcnQgZGVmYXVsdCBzb2NrZXRcbiJdLCJtYXBwaW5ncyI6IkFBQUE7QUFBQTtBQUFBO0FBQ0E7QUFFQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBRUE7QUFFQTtBQUFBO0FBQUE7QUFBQTtBQUFBO0FBR0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQUE7QUFDQTtBQUVBO0FBQ0E7QUFDQTtBQUFBO0FBQ0E7QUFBQTtBQUVBIiwic291cmNlUm9vdCI6IiJ9\n//# sourceURL=webpack-internal:///./js/socket.js\n");

/***/ }),

/***/ 0:
/*!*************************!*\
  !*** multi ./js/app.js ***!
  \*************************/
/*! no static exports found */
/***/ (function(module, exports, __webpack_require__) {

module.exports = __webpack_require__(/*! ./js/app.js */"./js/app.js");


/***/ })

/******/ });