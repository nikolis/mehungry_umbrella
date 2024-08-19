import _ from 'lodash'

let resizeHandler

export const ViewportResizeHooks = {

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
