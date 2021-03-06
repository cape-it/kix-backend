Feature: DELETE request to the /system/i18n/translations/:TranslationID/languages/:Language resource

  Background: 
    Given the API URL is __BACKEND_API_URL__
    Given the API schema files are located at __API_SCHEMA_LOCATION__
    Given I am logged in as agent user "admin" with password "Passw0rd"

  Scenario: delete translation language
    Given a i18n translation with
    When I create a translation language with
    Then the response code is 201   
    When I delete this translation language
    Then the response code is 204
    And the response has no content
    When I delete this i18n translation
    Then the response code is 204
    And the response has no content

