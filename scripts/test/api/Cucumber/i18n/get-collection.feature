 Feature: GET request to the /i18n/translations resource

  Background: 
    Given the API URL is __BACKEND_API_URL__
    Given the API schema files are located at __API_SCHEMA_LOCATION__
    Given I am logged in as agent user "admin" with password "Passw0rd"

  Scenario: get the list of existing i18n translations 
    When I query the collection of i18n translations
    Then the response code is 200
    And the response object is TranslationCollectionResponse


