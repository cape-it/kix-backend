Feature: DELETE request to the /system/communication/systemaddresses/:SystemAddressID resource

  Background: 
    Given the API URL is __BACKEND_API_URL__
    Given the API schema files are located at __API_SCHEMA_LOCATION__
    Given I am logged in as agent user "admin" with password "Passw0rd"

  Scenario: delete this systemaddress
    Given a systemaddress
    When I delete this systemaddress
    Then the response code is 204
    And the response has no content
