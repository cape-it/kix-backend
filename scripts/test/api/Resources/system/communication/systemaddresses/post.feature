Feature: POST request to the /system/communication/systemaddresses resource

  Background: 
    Given the API URL is __BACKEND_API_URL__
    Given the API schema files are located at __API_SCHEMA_LOCATION__
    Given I am logged in as agent user "admin" with password "Passw0rd"
    
  Scenario: create a systemaddress
    When I create a systemaddress 
    Then the response code is 201
    Then the response object is SystemAddressPostPatchResponse
    When I delete this systemaddress
    Then the response code is 204

