# Mehungry
## Case Study -> Posts 
### Considering the usage of first degree in-memory only storage to increase the performance of the part of the applications interact the most and use async jobs for actual database interactions 

1. To not spill the complexity the whole thing sould be view agnositic and it should recide in the a layer that we feel comfratable with uncertainity 
2. Users in reality based example shouldn't have to view the same list of posts in the same order but in order to get updates they need to subscribe to each individual post so this can be a reference point of when we need a post to be in-memory(when someone subscribes to it).
3. We need a strategy that is independent of any kind of user-based personalization strategy as this should be able to change without influencing the overal functionality of the system.
4. The interactive part of the Posts are in particular the voting and commenting part of the functinality so other parts of the api could be left as is 
  

### Proposal
When first user subscribes to first topic create the initial in-memory post list, insert the particular post into the cachce , and for every subscription by a user to a post insert the post to the cache 


## Basic Recipe Recommendations 
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

