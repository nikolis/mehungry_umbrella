export const SearchSelectHook = {
  mounted() {
    this.handleEvent(`set-value-${this.el.dataset.target}`, ({ value }) => {
      this.el.value = value
    })
  }
}
