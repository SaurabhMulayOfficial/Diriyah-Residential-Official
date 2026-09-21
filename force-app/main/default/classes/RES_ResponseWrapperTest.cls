/**
 * @description Test class for RES_ResponseWrapper
 *              Validates JSON deserialization, keyword remapping,
 *              and error logging functionality.
 */
@isTest
private class RES_ResponseWrapperTest {

    /**
     * @description Test deserialize with blank input
     */
    @isTest
    static void testDeserializeWithBlankInput() {
        Test.startTest();
        RES_ResponseWrapper result1 = RES_ResponseWrapper.deserialize(null);
        RES_ResponseWrapper result2 = RES_ResponseWrapper.deserialize('');
        RES_ResponseWrapper result3 = RES_ResponseWrapper.deserialize('   ');
        Test.stopTest();

        Assert.isNull(result1, 'Expected null for null input');
        Assert.isNull(result2, 'Expected null for empty string');
        Assert.isNull(result3, 'Expected null for whitespace string');
    }

    /**
     * @description Test deserialize with missing Return object
     */
    @isTest
    static void testDeserializeWithoutReturnObject() {
        String jsonWithoutReturn = '{"SomeOtherField": "value"}';

        Test.startTest();
        RES_ResponseWrapper result = RES_ResponseWrapper.deserialize(jsonWithoutReturn);
        Test.stopTest();

        Assert.isNull(result, 'Expected null when Return object is missing');
    }

    /**
     * @description Test deserialize with single item response
     */
    @isTest
    static void testDeserializeWithSingleItem() {
        String jsonResponse = '{' +
            '"Return": {' +
                '"item": {' +
                    '"type": "E",' +
                    '"id": "001",' +
                    '"Number": "123",' +
                    '"message": "Error occurred",' +
                    '"logNo": "LOG001",' +
                    '"logMsgNo": "MSG001",' +
                    '"messageV1": "Value1",' +
                    '"messageV2": "Value2",' +
                    '"messageV3": "Value3",' +
                    '"messageV4": "Value4",' +
                    '"parameter": "Param1",' +
                    '"row": "1",' +
                    '"field": "Field1",' +
                    '"System": "SAP"' +
                '}' +
            '}' +
        '}';

        Test.startTest();
        RES_ResponseWrapper result = RES_ResponseWrapper.deserialize(jsonResponse);
        Test.stopTest();

        Assert.isNotNull(result, 'Result should not be null');
        Assert.isNotNull(result.responseReturn, 'responseReturn should not be null');
        Assert.isNotNull(result.responseReturn.item, 'item list should not be null');
        Assert.areEqual(1, result.responseReturn.item.size(), 'Expected 1 item');

        RES_ResponseWrapper.ItemWrapper item = result.responseReturn.item[0];
        Assert.areEqual('E', item.type, 'Type should match');
        Assert.areEqual('001', item.id, 'ID should match');
        Assert.areEqual('123', item.messageNumber, 'Number should be remapped to messageNumber');
        Assert.areEqual('Error occurred', item.message, 'Message should match');
        Assert.areEqual('LOG001', item.logNo, 'LogNo should match');
        Assert.areEqual('MSG001', item.logMsgNo, 'LogMsgNo should match');
        Assert.areEqual('Value1', item.messageV1, 'MessageV1 should match');
        Assert.areEqual('Value2', item.messageV2, 'MessageV2 should match');
        Assert.areEqual('Value3', item.messageV3, 'MessageV3 should match');
        Assert.areEqual('Value4', item.messageV4, 'MessageV4 should match');
        Assert.areEqual('Param1', item.parameter, 'Parameter should match');
        Assert.areEqual('1', item.row, 'Row should match');
        Assert.areEqual('Field1', item.field, 'Field should match');
        Assert.areEqual('SAP', item.systemName, 'System should be remapped to systemName');
    }

    /**
     * @description Test deserialize with multiple items (array response)
     */
    @isTest
    static void testDeserializeWithMultipleItems() {
        String jsonResponse = '{' +
            '"Return": {' +
                '"item": [' +
                    '{' +
                        '"type": "E",' +
                        '"id": "001",' +
                        '"Number": "100",' +
                        '"message": "First error",' +
                        '"System": "SAP1"' +
                    '},' +
                    '{' +
                        '"type": "W",' +
                        '"id": "002",' +
                        '"Number": "200",' +
                        '"message": "Warning message",' +
                        '"System": "SAP2"' +
                    '},' +
                    '{' +
                        '"type": "S",' +
                        '"id": "003",' +
                        '"Number": "300",' +
                        '"message": "Success message",' +
                        '"System": "SAP3"' +
                    '}' +
                ']' +
            '}' +
        '}';

        Test.startTest();
        RES_ResponseWrapper result = RES_ResponseWrapper.deserialize(jsonResponse);
        Test.stopTest();

        Assert.isNotNull(result, 'Result should not be null');
        Assert.isNotNull(result.responseReturn, 'responseReturn should not be null');
        Assert.isNotNull(result.responseReturn.item, 'item list should not be null');
        Assert.areEqual(3, result.responseReturn.item.size(), 'Expected 3 items');

        // Verify first item
        RES_ResponseWrapper.ItemWrapper item1 = result.responseReturn.item[0];
        Assert.areEqual('E', item1.type, 'First item type should be E');
        Assert.areEqual('001', item1.id, 'First item ID should match');
        Assert.areEqual('100', item1.messageNumber, 'First item messageNumber should match');
        Assert.areEqual('First error', item1.message, 'First item message should match');
        Assert.areEqual('SAP1', item1.systemName, 'First item systemName should match');

        // Verify second item
        RES_ResponseWrapper.ItemWrapper item2 = result.responseReturn.item[1];
        Assert.areEqual('W', item2.type, 'Second item type should be W');
        Assert.areEqual('002', item2.id, 'Second item ID should match');
        Assert.areEqual('200', item2.messageNumber, 'Second item messageNumber should match');
        Assert.areEqual('Warning message', item2.message, 'Second item message should match');
        Assert.areEqual('SAP2', item2.systemName, 'Second item systemName should match');

        // Verify third item
        RES_ResponseWrapper.ItemWrapper item3 = result.responseReturn.item[2];
        Assert.areEqual('S', item3.type, 'Third item type should be S');
        Assert.areEqual('003', item3.id, 'Third item ID should match');
        Assert.areEqual('300', item3.messageNumber, 'Third item messageNumber should match');
        Assert.areEqual('Success message', item3.message, 'Third item message should match');
        Assert.areEqual('SAP3', item3.systemName, 'Third item systemName should match');
    }

    /**
     * @description Test deserialize with minimal fields
     */
    @isTest
    static void testDeserializeWithMinimalFields() {
        String jsonResponse = '{' +
            '"Return": {' +
                '"item": {' +
                    '"type": "S"' +
                '}' +
            '}' +
        '}';

        Test.startTest();
        RES_ResponseWrapper result = RES_ResponseWrapper.deserialize(jsonResponse);
        Test.stopTest();

        Assert.isNotNull(result, 'Result should not be null');
        Assert.isNotNull(result.responseReturn.item, 'item list should not be null');
        Assert.areEqual(1, result.responseReturn.item.size(), 'Expected 1 item');
        Assert.areEqual('S', result.responseReturn.item[0].type, 'Type should match');
    }

    /**
     * @description Test direct integration log creation
     *              Tests the underlying RES_IntegrationErrorLogger.log method
     */
    @isTest
    static void testLogErrorSuccess() {
        RES_IntegrationErrorLogger log = new RES_IntegrationErrorLogger(
            'TestService',
            'testMethod',
            'Test error message',
            '{"Content-Type": "application/json"}',
            'Account',
            '001000000000000',
            '{"test": "request"}',
            'POST',
            'TestRequest',
            1,
            'Client Side'
        );

        Test.startTest();
        RES_IntegrationErrorLogger.log(log);
        Test.stopTest();

        List<RES_Integration_Log__c> logs = [
            SELECT Id, RES_Callout_Service__c, RES_Error_Message__c, RES_Class_Method__c
            FROM RES_Integration_Log__c
            WHERE RES_Callout_Service__c = 'TestService'
        ];

        Assert.areEqual(1, logs.size(), 'Expected 1 log record');
        Assert.areEqual('Test error message', logs[0].RES_Error_Message__c, 'Error message should match');
        Assert.areEqual('testMethod', logs[0].RES_Class_Method__c, 'Class method should match');
    }

    /**
     * @description Test ResponseWrapper.logError exception handling wrapper
     *              Validates that the wrapper method catches exceptions gracefully
     */
    @isTest
    static void testLogErrorWithExceptionHandling() {
        RES_IntegrationErrorLogger validLog = new RES_IntegrationErrorLogger(
            'WrapperTest',
            'testMethod',
            'Wrapped error',
            '{}',
            'Contact',
            '003000000000000',
            '{}',
            'GET',
            'WrapperRequest',
            0,
            'Timeout'
        );

        Test.startTest();
        // Call through the wrapper method - should not throw
        try {
            RES_ResponseWrapper.logError(validLog);
            // If we reach here, the method executed without throwing
            Assert.isTrue(true, 'logError should execute without throwing exceptions');
        } catch (Exception e) {
            Assert.fail('ResponseWrapper.logError should catch all exceptions: ' + e.getMessage());
        }
        Test.stopTest();
    }

    /**
     * @description Test logError with invalid data to ensure exception handling
     *              Even with null/invalid data, the method should not throw
     */
    @isTest
    static void testLogErrorWithException() {
        RES_IntegrationErrorLogger log = new RES_IntegrationErrorLogger();

        Test.startTest();
        try {
            RES_ResponseWrapper.logError(log);
            Assert.isTrue(true, 'Method should handle exceptions gracefully');
        } catch (Exception e) {
            Assert.fail('Exception should be caught internally: ' + e.getMessage());
        }
        Test.stopTest();
    }

    /**
     * @description Test deserialize with empty Return.item
     */
    @isTest
    static void testDeserializeWithEmptyItemArray() {
        String jsonResponse = '{' +
            '"Return": {' +
                '"item": []' +
            '}' +
        '}';

        Test.startTest();
        RES_ResponseWrapper result = RES_ResponseWrapper.deserialize(jsonResponse);
        Test.stopTest();

        Assert.isNotNull(result, 'Result should not be null');
        Assert.isNotNull(result.responseReturn, 'responseReturn should not be null');
        Assert.isNotNull(result.responseReturn.item, 'item list should not be null');
        Assert.areEqual(0, result.responseReturn.item.size(), 'Expected 0 items');
    }
}
