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

### Patterns
#### Hierarchical Selection
When there is a need to get value from a series of sources and return the first that is currently not nil that some times arise when working with custome ui elements on forms and changes etc. The code could be stadardized like the following
- Put the values in a tuple {first-degree, second-degee, thrid-degree}
    ```
    case tuple do 
        {nil, nil, nil } ->
          whatever 
        {nil, nil, third-degree } ->
          third-degree
        {nil, second-degree, _ } ->
          second-degree
        {first-degree, _, _} ->
          third-degree
     end 
    ```
## Testing 

## Web App
- [Documentation](apps/mehungry_web/README.md)
## Core App 
- [Documentation](apps/mehungry/README.md)


##  Roadmap 

    *** Public user profile / user to user subscriptions 
    *** Basic Professional Account control screen / Presentation Ready 
    *** Basic Recommendation engine 
    *** Basic Ingredient Management Interface 
    *** Multi Language Translation in Ingredients  
    *** Multi Language Translation in Application
