# Mehungry.Umbrella

## Documentating the Food Data Parser resigning in apps/Mehungry/lib/mehungry/food_data_parser.ex 
(this is a toy project so the documentation for the time being is just for the context of the interview process)

The postgres password for the dev part is the default postgres postgres. 
1. mix deps.get 
2. mix ecto.create 
3. mix ecto.migrate 
4. mix run apps/mehungry/priv/repo/seeds.exs

After this the test for the parser should be running properly

## Case Study -> Posts 
### Considering the usage of first degree in-memory only storage to increase the performance of the part of the applications interact the most and use async jobs for actual database interactions 

1. To not spill the complexity the whole thing sould be view agnositic and it should recide in the a layer that we feel comfratable with uncertainity 
2. Users in reality based example shouldn't have to view the same list of posts in the same order but in order to get updates they need to subscribe to each individual post so this can be a reference point of when we need a post to be in-memory(when someone subscribes to it).
3. We need a strategy that is independent of any kind of user-based personalization strategy as this should be able to change without influencing the overal functionality of the system.
4. The interactive part of the Posts are in particular the voting and commenting part of the functinality so other parts of the api could be left as is 
  

### Proposal
When first user subscribes to first topic create the initial in-memory post list, insert the particular post into the cachce , and for every subscription by a user to a post insert the post to the cache 



##  Roadmap 

    *** Public user profile / user to user subscriptions 
    *** Basic Professional Account control screen / Presentation Ready 
    *** Basic Recommendation engine 
    *** Basic Ingredient Management Interface 
    *** Multi Language Translation in Ingredients  
    *** Multi Language Translation in Application
