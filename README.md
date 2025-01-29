# Mehungry.Umbrella

## Deployment 
### Database 
    - Engine PostgreSQL
    - Provider AwsRDS
### Application 
    - Docker 
    - Github Actions
    - AWS ECR 
    - AWS ECS 
## Coding Guidelines 
- Follow Default Creado guidelines 
- Build Live Components with a clear division between View (Render) and Update Code 
- Build Live Components View part be defining it's function in the order that they are invoked from the invoking function starting with the render
## Web App
- [Documentation](apps/mehungry_web/README.md)
## Core App 
 - [Documentation](apps/mehungry/README.md)


## Custom Components 
![Alt text](diagrams/SelectComponentDataFlow.jpg?raw=true "Select Diagram")


As can be shown by the diagram the Form id the middle man and holds all the necessary information. 

So we are limited buy the limitations of the relevant html components and their cappabilities of foldind data, we could not just have the form submit array data for multiple selected items, this can only happen through modifications in the data after they leave the form. 



    

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
