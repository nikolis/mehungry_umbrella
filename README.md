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
### Unit Tests
 Ex Unit 
### Integration tests
  Integration tests verify that different modules or services used by your application work well together. For example, it can be testing the interaction with the database or making sure that microservices work together as expected. These types of tests are more expensive to run as they require multiple parts of the application to be up and running.
### Functional tests
  Functional tests focus on the business requirements of an application. They only verify the output of an action and do not check the intermediate states of the system when performing that action.

  There is sometimes a confusion between integration tests and functional tests as they both require multiple components to interact with each other. The difference is that an integration test may simply verify that you can query the database while a functional test would expect to get a specific value from the database as defined by the product requirements. 
### End-to-end tests
End-to-end testing replicates a user behavior with the software in a complete application environment. It verifies that various user flows work as expected and can be as simple as loading a web page or logging in or much more complex scenarios verifying email notifications, online payments, etc...

End-to-end tests are very useful, but they're expensive to perform and can be hard to maintain when they're automated. It is recommended to have a few key end-to-end tests and rely more on lower level types of testing (unit and integration tests) to be able to quickly identify breaking changes.

### Performance testing
 In the context of the Phoenix Live Views it seem that there is no dominating trend on the approach when it comes to Load Testing/Performance Testing.
https://elixirforum.com/t/phoenix-liveview-load-testing-2024/62331
https://elixirforum.com/t/understanding-liveview-telemetry-events-for-load-performance-testing-w-artillery-and-playwright/64192
https://elixirforum.com/t/is-flame-well-suited-for-load-testing/61758
https://elixirforum.com/t/tsung-load-testing-phoenix-app/20723/2

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
