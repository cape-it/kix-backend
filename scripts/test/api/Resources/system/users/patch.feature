Feature: PATCH request to the /system/users/:UserID resource

  Background: 
    Given the API URL is __BACKEND_API_URL__
    Given the API schema files are located at __API_SCHEMA_LOCATION__
    Given I am logged in as agent user "admin" with password "Passw0rd"

  Scenario: update a user
    Given a user
    When I update this user
    Then the response code is 200
    And the response object is UserPostPatchResponse
#    When I delete this user
#    Then the response code is 204

