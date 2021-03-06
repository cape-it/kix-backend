Feature: GET request to the /system/dynamicfields/:DynamicFieldID resource

  Background: 
    Given the API URL is __BACKEND_API_URL__
    Given the API schema files are located at __API_SCHEMA_LOCATION__
    Given I am logged in as agent user "admin" with password "Passw0rd"
      
  Scenario: get an existing dynamicfield
    Given a dynamicfield
    When I get this dynamicfield
    Then the response code is 200
    And the attribute "DynamicField.Label" is "Due Date2ex2"    
    When I delete this dynamicfield
    Then the response code is 204
    And the response has no content


    
