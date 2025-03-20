# Mehungry.Umbrella

## Deployment 

### Database 
    - Engine PostgreSQL
    - Provider AwsRDS
    - In deployment be extra carefull of the Database url to eliminate any special characters in case of copy and paste like space character as they may lead to very confusing to debug problems *DATABASE_URL
    - When running the task in AWS ECS beware of the default secutiry-groups/subnets
    - Postgres version 14 is used / newer versions might not work out of the box with the current ecs set up
 

### Application 
    - Docker 
    - Github Actions
    - AWS ECR 
    - AWS ECS 

### Handling Database Migrations
The way it's handled in this project is by having a seperate 2 different processes in the deploymenty phase 
1) Is the normal deployment for the core app which is being done in 2 steps 
    a) First we create an docker-image (the builder) which has all the necessary build tools need for us to release the elixir applicatio but using lightweight OS identical to the deployment OS Alpine in this case.
    b) The building of the image that is actually going to be deployed inside the container created in step a 
2) A simpler deployment consisting from only one step which is the creation of a single docker container containing all the developement tools of elixir like mix etc.. and it just execute the mix migrate command 
    a) There is a specific task definition in ECS that is updated through the "migrate" step with the latest migrator-image 
    b) for this to work there is still the need to comment out the server: true in the Endpoint config in the prods.exs 
    c) The deployement contrary to the normal app of the Task should be run manually 


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
### Unit Tests
  Ex Unit 
### Integration tests / Smoke Test
  The domain of the integration/smoke tests in the context of phoenix application can be well represented through the tests genereted by a the generators whenever we use them to generate a new Module. 

### Regression Tests 
  Regression tests should be more related to the app's domain ex_unit ConnCase along with LiveViewTests  could still do the job, idealy whatever evades the basic Apis CRUD etc .. though would be hierarchically differentiated so that it only runs in the case that all the Previous Layer(Integration/Smoke) Tests are sucessfull 

### Functional tests
  When it comes to functional tests for a phoenix application in the context of LiveViews the only promising approach looks like is wallaby and thus we use wallaby Tests to perform Functional Tests in the context of this project. Ideally this would still layered on top of the previous test layer and thus only run through a sucessfull pass of all Regression Tests 

### End-to-end tests
  ...

### Performance testing
 In the context of the Phoenix Live Views it seem that there is no dominating trend on the approach when it comes to Load Testing/Performance Testing.
- [phoenix liveview load testing](https://elixirforum.com/t/phoenix-liveview-load-testing-2024/62331)
- [phoenix liveview telemetry](https://elixirforum.com/t/understanding-liveview-telemetry-events-for-load-performance-testing-w-artillery-and-playwright/64192)
- [phoenix liveview load test with flame ?](https://elixirforum.com/t/is-flame-well-suited-for-load-testing/61758)
- [phoenix testing with tsung ?](https://elixirforum.com/t/tsung-load-testing-phoenix-app/20723/2)

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
