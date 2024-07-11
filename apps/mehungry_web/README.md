# MehungryWeb

## Navigation Highlighting 

In order to have a more spa feeling into the project all the "after login" pages are put on the same live session and instead the navigation highlighting is handled into the Javascript side using LiveSocket and Javascript's native Proxy class to intercept url chagnes


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

### Basic Recipe Recommendations 
    Problem definition: with limited developement resources for this project as well as limited cloud budget we need to find a basic solution to provide users with decent recommendations. 
    Proposal: Ask users directly for their food prefereneces through asking them their preference of specific ingredient categories i.e "Meats, Vetables , Grains etc" to get a first impression and use this data to provide with first line of recommendations 
    Important Factors: Given the circomstances we can't build a powerfull recommendations engine but we can still filter through the whole set using user direct input, users most probably won't take the time complete the whole set of questions or preferences so whenever there is opportunity we need to prioritize the most imporant 
        * Preferences Regarding meet 
        * Preferences Regarding diary
        * Preferences Regarding See Food and Fish 
        * Alcohol 
        * Imply indeference for the rest of them 
    Given the above prioritization the user would have 5 possible answers that would represent 0 -> Not at all, 1 -> Not a fun, 2 -> Indiferent , 3 -> A fun , 4 -> Absolute Fun.  Given Users preferences on at least 3 ingredient categories we can assume that the a user selecting "0" in a food category should represent serious food categories like health related diatery restrictions or ideology related diatery restrictions and avoid at all cost to show the user with such content that includes this ingredients. 
    Probably solution: 
        * Come up with a grading system that would grade recipes according the ingredients they contain
        * Come up with a grading system that would grade users according their ingredient preferences 
        * Grade probable posts(containing recipes) in a way that if a user has selected "0" in a category that the recipes contains then the recipe score should be "0" 
        * Filter out the recipes that graded with zero and then present the result in order
        user grading system    0  0.5 1 1.5 2
        recipe initial system  0  1

        user example array %{"Meat": 0, "Vefetables": 2, "Fruits": 2, "Diary": 0.5, "See food": 0, "Grains": 2}
        
        recipe example arr %{"Meat": 1, "Vegetable": 1, "Fruits": 1}
        user sub_array {"Meat": 0, "Vegetable": 2, "Fruits": 2}
                Grade: 1*0 * 1*2 * 1*2  = 0

        recipe example arr %{"Vegetable": 1, "Grains": 1, "Seasoning": 1}
        user sub_array {"Vegetable": 2, "Grains": 1, "Seasoning": 1}
                Grade  2*1 * 1*2 * 1*1 = 4

        recipe example arr %{"Vegetable": 1, "Grains": 1, "Seasoning": 1,  "Dairy": 1}
        user sub_array {"Vegetable": 2, "Grains": 2, "Seasoning": 1, "Dairy": 0.5}
                Grade  2*1 * 2*1 * 1*1 * 0.5*1 = 2
                     
 
    Recommendations are going to start with the absolute basics 
        * The application is going to ask users bunch of basic questions and imply some fundemental settings about them For i.e "Are you Vegeterian, Vegan, Pescatarian"
        * Do you have any dietery specialties i.e "Lactose intolerance ..."
        And from this basic questions would imply the very basic user grading array, this would be enough to get the basic filtering for the user and from that point on the user can chose to add more dietery preferencies through their profile. 

    Implementation: 
        * Upon Recipe Creation the back-end system should calculate the recipe grade array and store it to inside the basic recipe record.
