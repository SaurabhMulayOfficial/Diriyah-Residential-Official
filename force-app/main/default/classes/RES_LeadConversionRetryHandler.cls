/**
 * ==============================================================================
 * Class Name    : RES_LeadConversionRetryHandler
 * Description   : Handles retry logic for Lead conversion.
 *                 Extracted from RES_LeadConversionQueueable for testability
 *                 and separation of concerns.
 *
 * Author        : Roshan Jambhule
 * Company       : Globant Inc
 * Created Date  : June 28, 2026
 * Version       : 1.0 (NEW - Non-breaking)
 * ==============================================================================
 */
public with sharing class RES_LeadConversionRetryHandler {
    
    public static final Integer DEFAULT_MAX_RETRIES = 5;
    private static final String CLASS_NAME = 'RES_LeadConversionRetryHandler';

    /**
     * @description Determines if should retry and handles retry logic
     *              Called when SLA status is not 'Met' for all leads.
     *
     * @param leadsNotReady List of leads not ready for conversion
     * @param retryCount Current retry attempt count
     * @param allLeadsForRetry All leads to retry
     * @return Boolean - true if retry was enqueued, false otherwise
     */
    public static Boolean handleRetry(
        List<Lead> leadsNotReady, 
        Integer retryCount, 
        List<Lead> allLeadsForRetry) {
        
        Integer maxRetries = getMaxRetriesFromLabel();
        
        if (retryCount < maxRetries && Limits.getQueueableJobs() == 0) {
            logRetryAttempt(leadsNotReady, retryCount, maxRetries);
            System.enqueueJob(new RES_LeadConversionQueueable(allLeadsForRetry, retryCount + 1));
            return true;
        } else {
            logConversionFailure(leadsNotReady, maxRetries);
            return false;
        }
    }

    /**
     * @description Handles exception retry logic
     *              Called when exception occurs during lead conversion.
     *
     * @param ex Exception caught during conversion
     * @param retryCount Current retry attempt count
     * @param leadsToRetry Leads to retry
     * @return Boolean - true if retry was enqueued
     */
    public static Boolean handleExceptionRetry(Exception ex, Integer retryCount, List<Lead> leadsToRetry) {
        System.debug(LoggingLevel.ERROR, CLASS_NAME + ': ' + ex.getMessage());
        
        Integer maxRetries = getMaxRetriesFromLabel();
        if (retryCount < maxRetries && Limits.getQueueableJobs() == 0) {
            logRetryAttempt(leadsToRetry, retryCount, maxRetries);
            System.enqueueJob(new RES_LeadConversionQueueable(leadsToRetry, retryCount + 1));
            return true;
        }
        return false;
    }

    /**
     * @description Logs conversion failure after max retries exhausted
     *
     * @param leads List of leads that failed to convert
     * @param maxRetries Maximum retry attempts
     */
    public static void logConversionFailure(List<Lead> leads, Integer maxRetries) {
        String leadIds = '';
        for (Lead l : leads) {
            leadIds += l.Id + ',';
        }
        System.debug(LoggingLevel.WARN, 'Conversion aborted after ' + maxRetries + ' retries. Leads: ' + leadIds);
    }

    /**
     * @description Logs retry attempt for debugging
     *
     * @param leads List of leads being retried
     * @param currentRetry Current retry number
     * @param maxRetries Maximum retries allowed
     */
    public static void logRetryAttempt(List<Lead> leads, Integer currentRetry, Integer maxRetries) {
        System.debug(LoggingLevel.INFO, 'Retrying lead conversion - Attempt ' + (currentRetry + 1) + ' of ' + maxRetries);
    }

    /**
     * @description Reads max retries from custom label with validation
     *
     * @return Integer Max retries (1-10, default 5)
     */
    public static Integer getMaxRetriesFromLabel() {
        try {
            String labelValue = System.Label.RES_Lead_Conversion_Max_Retries;
            if (String.isBlank(labelValue)) {
                return DEFAULT_MAX_RETRIES;
            }
            Integer maxRetries = Integer.valueOf(labelValue);
            if (maxRetries < 1 || maxRetries > 10) {
                return DEFAULT_MAX_RETRIES;
            }
            return maxRetries;
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'Error reading max retries label: ' + ex.getMessage());
            return DEFAULT_MAX_RETRIES;
        }
    }
}