# MehungryWeb
## Custom Components 
![Alt text](diagrams/SelectComponentDataFlow.jpg?raw=true "Select Diagram")


As can be shown by the diagram the Form id the middle man and holds all the necessary information. 

So we are limited buy the limitations of the relevant html components and their cappabilities of foldind data, we could not just have the form submit array data for multiple selected items, this can only happen through modifications in the data after they leave the form. 


## Navigation Highlighting 

In order to have a more spa feeling into the project all the "after login" pages are put on the same live session and instead the navigation highlighting is handled into the Javascript side using LiveSocket and Javascript's native Proxy class to intercept url chagnes
![Alt text](diagrams/LiveViewNavHighlighting.jpg?raw=true "Select Diagram")

## Modal Handling
    There are two possible aproaches investigated for how to implment modals in this porject!
### Aproach one is CSS + LiveViewJs
 This aproach uses (Is currently being utilized on the Browse Recipes to present recipe details inside the modal 
  * the css to provide the presentation layer for the modal to have the expected appearance in the screen
  * the Phoenix.LiveView.JS to push events to the hosting live-view/live-component like close-modal etc

### The second approach is CSS + Client Hooks 
   * the css to provide the presentation layer for the modal to have the expected appearance in the screen
   * the Phoenix client Hooks to load the Javascript behaviour like push events

### The phoenix pre-existing  core_components way
    As of phoenix version 1.7 phoenix provide a reusable component in the core_components.ex and which is fully implemented taking account accessibility and also has the fade/in-out animation so the project will switch to use those intead in the removing_select2_improving_css branch (for future references)
