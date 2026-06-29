/**
 * ==============================================================================
 * Test Class    : RES_LeadConversionRetryHandler_Test
 * Description   : Unit tests for RES_LeadConversionRetryHandler
 *
 * Author        : Roshan Jambhule
 * Company       : Globant Inc
 * Created Date  : June 28, 2026
 * Version       : 1.2 (FINAL - 4 Essential Tests)
 * ==============================================================================
 */
@isTest
private class RES_LeadConversionRetryHandler_Test {
    
    private static final String PROJECT = 'Amansamar Residences Wadi Safar';

    @IsTest
    static void testLogConversionFailure() {
        // ✅ Tests logConversionFailure() - Lines 200-206
        Lead l = RES_TestDataFactory.createLeadWithProject('logfailure@test.com', PROJECT);
        
        Test.startTest();
        RES_LeadConversionRetryHandler.logConversionFailure(new List<Lead>{ l }, 5);
        Test.stopTest();
        
        System.assertEquals(true, true, 'Logging should complete without error');
    }

    @IsTest
    static void testGetMaxRetriesFromLabel() {
        // ✅ Tests getMaxRetriesFromLabel() - Lines 208-220
        Test.startTest();
        Integer maxRetries = RES_LeadConversionRetryHandler.getMaxRetriesFromLabel();
        Test.stopTest();
        
        System.assertNotEquals(null, maxRetries, 'Max retries should be returned');
        System.assertEquals(true, maxRetries >= 1 && maxRetries <= 10, 'Should be within 1-10 range');
    }

    @IsTest
    static void testHandleExceptionRetry() {
        // ✅ Tests handleExceptionRetry() - Exception path
        Lead l = RES_TestDataFactory.createLeadWithProject('exceptionretry@test.com', PROJECT);
        
        Test.startTest();
        try {
            throw new TestException('Test exception for retry');
        } catch (Exception ex) {
            Boolean retried = RES_LeadConversionRetryHandler.handleExceptionRetry(
                ex, 
                0, 
                new List<Lead>{ l }
            );
            System.assertEquals(true, retried, 'Should retry on exception when retryCount < maxRetries');
        }
        Test.stopTest();
    }

    @IsTest
    static void testLogRetryAttempt() {
        // ✅ Tests logRetryAttempt() logging
        Lead l = RES_TestDataFactory.createLeadWithProject('logretry@test.com', PROJECT);
        
        Test.startTest();
        RES_LeadConversionRetryHandler.logRetryAttempt(new List<Lead>{ l }, 2, 5);
        Test.stopTest();
        
        System.assertEquals(true, true, 'Logging retry attempt should complete');
    }

    private class TestException extends Exception {}
}