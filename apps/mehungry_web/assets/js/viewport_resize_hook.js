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
    this.pushEvent('viewport_resize', {
      width: window.innerWidth,
      height: window.innerHeight
    })
  },

  turbolinksDisconnected () {
    window.removeEventListener('resize', resizeHandler)
  }
}
